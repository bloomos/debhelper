package Debian::Debhelper::Commands::dh_fixperms;
use strict;
use warnings;

use Config;
use Debian::Debhelper::Dh_Lib;

sub patterns2find_expr {
	return sprintf('\\( -name %s \\)', join(' -o -name ', map { "'$_'" } @_));
}


my $vendorlib = substr $Config{vendorlib}, 1;
my $vendorarch = substr $Config{vendorarch}, 1;
my @executable_files_dirs = (
	qw{usr/bin bin usr/sbin sbin usr/games etc/init.d},
);
my @mode_0644_patterns = (
	# Libraries and related files
	'*.so.*', '*.so', '*.la', '*.a',
	# Web application related files
	'*.js', '*.css', '*.scss', '*.sass',
	# Images
	'*.jpeg', '*.jpg', '*.png', '*.gif',
	# OCaml native-code shared objects
	'*.cmxs',
	# Node bindings
	'*.node',
);
my @mode_0755_patterns = (
	# None for Debian
);
my $find_exclude_options='-true';
if (defined($dh{EXCLUDE_FIND}) && $dh{EXCLUDE_FIND} ne '') {
	$find_exclude_options="! \\( $dh{EXCLUDE_FIND} \\)";
}

sub find_and_reset_perm {
	my ($in_dirs, $mode, $raw_find_expr, $raw_find_expr_late) = @_;
	my (@dirs, $dir_string);
	if (ref ($in_dirs) ) {
		@dirs = grep { -d } @{$in_dirs};
		return if not @dirs;
	} else {
		return if not -d $in_dirs;
		@dirs = ($in_dirs);
	}
	$dir_string = escape_shell(@dirs);
	$raw_find_expr //= '';
	$raw_find_expr_late //= '-true';
	complex_doit("find ${dir_string} ${raw_find_expr} -a ${find_exclude_options} -a ${raw_find_expr_late} -print0",
		"2>/dev/null | xargs -0r chmod ${mode}");
}

sub process_packages_in_parallel {
	foreach my $package (@_) {
		my $tmp=tmpdir($package);

		next if not -d $tmp;

		# General permissions fixing.
		complex_doit("find $tmp ${find_exclude_options} -print0",
			"2>/dev/null | xargs -0r chown --no-dereference 0:0") if should_use_root();
		find_and_reset_perm($tmp, 'go=rX,u+rw,a-s', '! -type l');

		# Fix up permissions in usr/share/doc, setting everything to not
		# executable by default, but leave examples directories alone.
		find_and_reset_perm("${tmp}/usr/share/doc", '0644', '-type f', "! -regex '$tmp/usr/share/doc/[^/]*/examples/.*'");
		find_and_reset_perm("${tmp}/usr/share/doc", '0755', '-type d');

		# Manpages, include file, desktop files, etc., shouldn't be executable
		find_and_reset_perm([
			"${tmp}/usr/share/man",
			"${tmp}/usr/include",
			"${tmp}/usr/share/applications",
			"${tmp}/usr/share/lintian/overrides",
		], '0644', '-type f');

		# nor should perl modules.
		find_and_reset_perm(["${tmp}/${vendorarch}", "${tmp}/${vendorlib}"],
			'a-X', "-type f -perm -5 -name '*.pm'");

		find_and_reset_perm($tmp, '0644', '-type f ' . patterns2find_expr(@mode_0644_patterns)) if @mode_0644_patterns;
		find_and_reset_perm($tmp, '0755', '-type f ' . patterns2find_expr(@mode_0755_patterns)) if @mode_0755_patterns;

		# Programs in the bin and init.d dirs should be executable..
		find_and_reset_perm([map { "${tmp}/$_"} @executable_files_dirs], 'a+x', '-type f');

		# ADA ali files should be mode 444 to avoid recompilation
		find_and_reset_perm("${tmp}/usr/lib", 'uga-w', "-type f -name '*.ali'");

		if ( -d "$tmp/usr/lib/nodejs/") {
			my @nodejs_exec_patterns = qw(*/cli.js */bin.js);
			my @exec_files = grep {
				not excludefile($_) and -f $_;
			} glob_expand(["$tmp/usr/lib/nodejs"], \&glob_expand_error_handler_silently_ignore, @nodejs_exec_patterns);
			reset_perm_and_owner(0755, @exec_files)
		}

		if ( -d "$tmp/usr/share/bug/$package") {
			complex_doit("find $tmp/usr/share/bug/$package -type f",
				"! -name 'script' ${find_exclude_options} -print0",
				"2>/dev/null | xargs -0r chmod 644");
			if ( -f "$tmp/usr/share/bug/$package/script" ) {
				reset_perm_and_owner(0755, "$tmp/usr/share/bug/$package/script");
			}
		} elsif ( -f "$tmp/usr/share/bug/$package" ) {
			reset_perm_and_owner(0755, "$tmp/usr/share/bug/$package");
		}

		# Files in $tmp/etc/sudoers.d/ must be mode 0440.
		find_and_reset_perm("${tmp}/etc/sudoers.d", '0440', "-type f ! -perm 440");
	}
};

1;