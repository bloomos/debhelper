package Dpkg::BuildDriver::Dhsequencerpoc;
use strict;
use warnings;

use Dpkg::Gettext;
use Dpkg::ErrorHandling;
use Dpkg::Path qw(find_command);

use Debian::Debhelper::Dh_Lib qw(%dh compat getpackages);
use Debian::Debhelper::Dh_Version;
use Debian::Debhelper::SequencerUtil;
use Debian::Debhelper::DH::SequenceState;

our $VERSION = '0.0.0~git-checkout';

eval {
	require Debian::Debhelper::Dh_Version;
	$VERSION = $Debian::Debhelper::Dh_Version::version;
};


sub new {
    my ($this, %opts) = @_;
    my $class = ref($this) || $this;

    my $self = {
	    ctrl                  => $opts{ctrl},
	    '_init_sequence_type' => undef,
    };
    bless $self, $class;

    return $self;
}

sub init {}

sub _init {
	my ($self, $task) = @_;
	my $sequence_type = sequence_type($task);
	if ($self->{'_init_sequence_type'}) {
		error("Only one target can be called (use R³=no)");
	}
	delete local $ENV{'DH_OPTIONS'};
	delete local $ENV{'DH_INTERNAL_OPTIONS'};
	local @ARGV = ();
	if ($sequence_type eq 'arch') {
		@ARGV = ('-a');
	} elsif ($sequence_type eq 'indep') {
		@ARGV = ('-i');
	}
	Debian::Debhelper::Dh_Lib::init(
		# Disable complaints about unknown options; they are passed on to
		# the debhelper commands.
		ignore_unknown_options => 1,
		# Bundling does not work well since there are unknown options.
		bundling => 0,
		internal_parse_dh_sequence_info => 1,
		inhibit_log => 1,
	);
	return;
}

sub run_task {
	my ($self, $task) = @_;

	$self->_init($task);

	my $sequence_unpack_flags = 0;
	my @packages = @{$dh{DOPACKAGES}};
	my @arch_packages = getpackages('arch');
	my @indep_packages = getpackages('indep');
	my (@addons, %startpoint, %logged);

	info("Using the Dhsequencerpoc Build-Driver");

	# Start with a clean slate to avoid backwards compat getting in our way of the PoC.
	error("The dh sequencer Build-Driver requires compat 12 or later")
		if compat(11);

	if ($task eq 'build-arch' || $task eq 'install-arch' || $task eq 'binary-arch') {
		push(@Debian::Debhelper::DH::SequenceState::options, "-a");
		# as an optimization, remove from the list any packages
		# that are not arch dependent
		@packages = @arch_packages;
	} elsif ($task eq 'build-indep' || $task eq 'install-indep' || $task eq 'binary-indep') {
		push(@Debian::Debhelper::DH::SequenceState::options, "-i");
		# ditto optimization for arch indep
		@packages = @indep_packages
	}

	load_sequence_addon('root-sequence', SEQUENCE_TYPE_BOTH);
	if (not @arch_packages) {
		$sequence_unpack_flags = FLAG_OPT_SOURCE_BUILDS_NO_ARCH_PACKAGES;
	} elsif (not @indep_packages) {
		$sequence_unpack_flags = FLAG_OPT_SOURCE_BUILDS_NO_INDEP_PACKAGES;
	}

	# Disable build-stamp to simplify the code
	@addons = compute_selected_addons($task, '-build-stamp');

	# Load addons, which can modify sequences.
	foreach my $addon (@addons) {
		my $addon_name = $addon->{'name'};
		my $addon_type = $addon->{'addon-type'};
		load_sequence_addon($addon_name, $addon_type);
	}

	if (%Debian::Debhelper::DH::SequenceState::commands_added_by_addon) {
		while (my ($cmd, $addon) = each(%Debian::Debhelper::DH::SequenceState::commands_added_by_addon)) {
			my $addon_type = $addon->{'addon-type'};
			if ($addon_type eq 'indep') {
				unshift(@{$Debian::Debhelper::DH::SequenceState::command_opts{$cmd}}, '-i');
			} elsif ($addon_type eq 'arch') {
				unshift(@{$Debian::Debhelper::DH::SequenceState::command_opts{$cmd}}, '-a');
			}
		}
	}

	if (! exists($Debian::Debhelper::DH::SequenceState::sequences{$task})) {
		error("Unknown sequence $task (choose from: ".
			join(" ", sort(keys(%Debian::Debhelper::DH::SequenceState::sequences))).")");
	}

	my ($rules_targets, $full_sequence) = unpack_sequence(
		\%Debian::Debhelper::DH::SequenceState::sequences,
		$task,
		1,  # We always inline as the sequencer only use the debian/rules for overrides/hooks
		{},
		$sequence_unpack_flags,
	);

	error("Internal error; ${task} contained opaque targets but they should have been inlined!?")
		if @{$rules_targets};

	check_for_obsolete_commands($full_sequence);

	%startpoint = compute_starting_point_in_sequences(\@packages, $full_sequence, \%logged);

	run_through_command_sequence($full_sequence, \%startpoint, \%logged,
		\@Debian::Debhelper::DH::SequenceState::options,
		\@packages, \@arch_packages, \@indep_packages, 1);

	return;
}

1;
