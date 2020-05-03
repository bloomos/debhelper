#!/usr/bin/perl
package Debian::Debhelper::Dh_Lib::Test;
use strict;
use warnings;
use Test::More;

use File::Basename qw(dirname);
use lib dirname(__FILE__);
use Test::DH;

use Debian::Debhelper::Dh_Lib qw(!dirname);

plan(tests => 2);


sub ok_autoscript_result {
	ok(-f 'debian/testpackage.postinst.debhelper');
	open(my $fd, '<', 'debian/testpackage.postinst.debhelper') or die("open test-poinst: $!");
	my (@c) = <$fd>;
	close($fd);
	like(join('',@c), qr{update-rc\.d test-script test parms with"quote >/dev/null});
}


each_compat_subtest {

	ok(autoscript('testpackage', 'postinst', 'postinst-init',
				  's/#SCRIPT#/test-script/g; s/#INITPARMS#/test parms with\\"quote/g'));
	ok_autoscript_result;

	ok(rm_files('debian/testpackage.postinst.debhelper'));

	ok(autoscript('testpackage', 'postinst', 'postinst-init',
				  sub { s/\#SCRIPT\#/test-script/g; s/\#INITPARMS\#/test parms with"quote/g } ));
	ok_autoscript_result;

	ok(rm_files('debian/testpackage.postinst.debhelper'));

	ok(autoscript('testpackage', 'postinst', 'postinst-init',
				  { 'SCRIPT' => 'test-script', 'INITPARMS' => 'test parms with"quote' } ));
	ok_autoscript_result;

	ok(rm_files('debian/testpackage.postinst.debhelper'));
};

$ENV{'FOO'} = "test";
my @SUBST_TEST_OK = (
	['unchanged', 'unchanged'],
	["unchanged\${\n}", "unchanged\${\n}"],  # Newline is not an allowed part of ${}
	['raw dollar-sign ${}', 'raw dollar-sign $'],
	['${Dollar}${Space}${Dollar}', '$ $'],
	['Hello ${env:FOO}', 'Hello test'],
	['${Dollar}{Space}${}{Space}', '${Space}${Space}'],  # We promise that ${Dollar}/${} never cause recursion
	['/usr/lib/${DEB_HOST_MULTIARCH}', '/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH')],
	[
		'/usr/lib/${DEB_HOST_MULTIARCH}/${package}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/foo',
		{'package' => 'foo'}
	],
	[
		'/usr/lib/${DEB_HOST_MULTIARCH}/${source}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/debhelper',
		{'package' => 'foo'}
	],

	# Externally provided variables
	[
		'${ext:debhelper-examples:lib-ma-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH'),
	],
	[
		'${ext:debhelper-examples:lib-ma-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH'),
	],
	[
		'${ext:debhelper-examples:foo-plugin-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/foo/plugins',
	],

	# Externally provided package specific variables (for package foo)
	[
		'${ext:debhelper-examples:pkg-lib-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/foo',
		{'package' => 'foo'},
	],
	[
		'${ext:debhelper-examples:pkg-plugin-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/foo/plugins',
		{'package' => 'foo'},
	],
	[
		'${ext:debhelper-examples:pkg-plugin-baz-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/foo/plugins/baz',
		{'package' => 'foo'},
	],
	# Externally provided package specific variables (for package bar)
	[
		'${ext:debhelper-examples:pkg-lib-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/bar',
		{'package' => 'bar'},
	],
	[
		'${ext:debhelper-examples:pkg-plugin-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/bar/plugins',
		{'package' => 'bar'},
	],
	[
		'${ext:debhelper-examples:pkg-plugin-baz-dir}',
		'/usr/lib/' . dpkg_architecture_value('DEB_HOST_MULTIARCH') . '/bar/plugins/baz',
		{'package' => 'bar'},
	],

	# Externally provided conditional package specific variables (for package debhelper)
	[
		'${ext:debhelper-examples:baz-feature-pkgdir}',
		'/usr/share/baz/debhelper',
		{'package' => 'debhelper'},
	],
	[
		'${ext:debhelper-examples:baz-feature-basedir}',
		'/usr/share/baz',
		{'package' => 'debhelper'},
	],
	[
		'${ext:debhelper-examples:only-available-on-arch-all}',
		'/usr/share/baz/all',
		{'package' => 'debhelper'},
	],
);

each_compat_subtest {
	for my $test (@SUBST_TEST_OK) {
		my ($input, $expected_output, $params) = @{$test};
		my $actual_output = Debian::Debhelper::Dh_Lib::_variable_substitution($input, 'test', $params);
		is($actual_output, $expected_output, qq{${input}" => "${actual_output}" (should be: "${expected_output})"});
	}
};
