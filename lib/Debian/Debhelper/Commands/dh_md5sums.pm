package Debian::Debhelper::Commands::dh_md5sums;
use strict;
use warnings;

use Debian::Debhelper::Dh_Lib;

sub process_packages_in_parallel {
	foreach my $package (@_) {
		next if is_udeb($package);

		my $dbgsym_tmp = dbgsym_tmpdir($package);
		my $tmp=tmpdir($package);

		install_dir("$tmp/DEBIAN");

		# Check if we should exclude conffiles.
		my %conffiles;
		if (! $dh{INCLUDE_CONFFILES} && -r "$tmp/DEBIAN/conffiles") {
			# Generate exclude regexp.
			open(my $fd, '<', "$tmp/DEBIAN/conffiles")
				or error("open $tmp/DEBIAN/conffiles failed: $!");
			while (my $line = <$fd>) {
				chomp($line);
				$line =~ s/^\///;
				$conffiles{$line} = 1;
			}
			close($fd);
		}

		generate_md5sums_file($tmp, \%conffiles);
		if ( -d $dbgsym_tmp) {
			install_dir("${dbgsym_tmp}/DEBIAN");
			generate_md5sums_file($dbgsym_tmp);
		}
	}
};

sub generate_md5sums_file {
	my ($tmpdir, $conffiles) = @_;
	my $find_pid = open(my $find_fd, '-|') // error("fork failed: $!");
	my (@files, $pipeline_pid);
	if (not $find_pid) {
		# Child
		chdir($tmpdir) or error("chdir($tmpdir) failed: $!");
		exec { 'find' } 'find', '-type', 'f', '!', '-regex', './DEBIAN/.*', '-printf', "%P\\0";
	}
	local $/ = "\0";  # NUL-terminated input/"lines"
	while (my $line = <$find_fd>) {
		chomp($line);
		next if excludefile($line);
		next if $conffiles and %{$conffiles} and exists($conffiles->{$line});
		push(@files, $line);
	}
	close($find_fd) or error_exitcode("find -type f ! -regex './DEBIAN/.*' -printf '%P\\0'");
	@files = sort(@files);
	verbose_print("cd $tmpdir >/dev/null && " . q{xargs -r0 md5sum | perl -pe 'if (s@^\\\\@@) { s/\\\\\\\\/\\\\/g; }' > DEBIAN/md5sums});
	$pipeline_pid = open(my $pipeline_fd, '|-') // error("fork failed: $!");
	if (not $pipeline_pid) {
		# Child
		chdir($tmpdir) or error("chdir($tmpdir) failed: $!");
		exec { 'sh' } '/bin/sh', '-c', q{xargs -r0 md5sum | perl -pe 'if (s@^\\\\@@) { s/\\\\\\\\/\\\\/g; }' > DEBIAN/md5sums};
	}

	printf {$pipeline_fd} "%s\0", $_ for @files;  # @files include NUL-terminator
	close($pipeline_fd) or error_exitcode("cd $tmpdir >/dev/null && xargs -r0 md5sum | perl -pe 'if (s@^\\\\@@) { s/\\\\\\\\/\\\\/g; }' > DEBIAN/md5sums");
	reset_perm_and_owner(0644, "${tmpdir}/DEBIAN/md5sums");
	return;
}


1;