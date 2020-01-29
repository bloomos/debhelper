package Debian::Debhelper::Commands::dh_gencontrol;
use strict;
use warnings;

use Errno qw(ENOENT);
use Debian::Debhelper::Dh_Lib;


sub ensure_substvars_are_present {
	my ($file, @substvars) = @_;
	my (%vars, $fd);
	return 1 if $dh{NO_ACT};
	if (open($fd, '+<', $file)) {
		while (my $line = <$fd>) {
			my $k;
			($k, undef) = split(m/=/, $line, 2);
			$vars{$k} = 1 if $k;
		}
		# Fall-through and append the missing vars if any.
	} else {
		error("open(${file}) failed: $!") if $! != ENOENT;
		open($fd, '>', $file) or error("open(${file}) failed: $!");
	}

	for my $var (@substvars) {
		if (not exists($vars{$var})) {
			verbose_print("echo ${var}= >> ${file}");
			print ${fd} "${var}=\n";
			$vars{$var} = 1;
		}
	}
	close($fd) or error("close(${file}) failed: $!");
	return 1;
}

sub process_packages_in_parallel {
	foreach my $package (@_) {
		my $tmp=tmpdir($package);
		my $ext=pkgext($package);
		my $dbgsym_info_dir = "debian/.debhelper/${package}";
		my $dbgsym_tmp = dbgsym_tmpdir($package);

		my $substvars="debian/${ext}substvars";

		my $changelog=pkgfile($package,'changelog');
		if (! $changelog) {
			$changelog='debian/changelog';
		}

		install_dir("$tmp/DEBIAN");

		# avoid gratuitous warnings
		ensure_substvars_are_present($substvars, 'misc:Depends', 'misc:Pre-Depends');

		my (@debug_info_params, $build_ids, @multiarch_params);
		if ( -d $dbgsym_info_dir ) {
			$build_ids = read_dbgsym_build_ids($dbgsym_info_dir);
		}

		if ( -d $dbgsym_tmp) {
			my $multiarch = package_multiarch($package);
			my $section = package_section($package);
			my $replaces = read_dbgsym_migration($dbgsym_info_dir);
			my $component = '';
			if ($section =~ m{^(.*)/[^/]+$}) {
				$component = "${1}/";
				# This should not happen, but lets not propagate the error
				# if does.
				$component = '' if $component eq 'main/';
			}

			# Remove and override more or less every standard field.
			my @dbgsym_options = (qw(
				-UPre-Depends -URecommends -USuggests -UEnhances -UProvides -UEssential
				-UConflicts -DPriority=optional -UHomepage -UImportant
				-UBuilt-Using -DAuto-Built-Package=debug-symbols
			),
				"-DPackage=${package}-dbgsym",
				"-DDepends=${package} (= \${binary:Version})",
				"-DDescription=debug symbols for ${package}",
				"-DBuild-Ids=${build_ids}",
				"-DSection=${component}debug",
			);
			push(@dbgsym_options, "-DPackage-Type=${\DBGSYM_PACKAGE_TYPE}")
				if DBGSYM_PACKAGE_TYPE ne DEFAULT_PACKAGE_TYPE;
			# Disable multi-arch unless the original package is an
			# multi-arch: same package.  In all other cases, we do not
			# need a multi-arch value.
			if ($multiarch ne 'same') {
				push(@dbgsym_options, '-UMulti-Arch');
			}
			# If the dbgsym package is replacing an existing -dbg package,
			# then declare the necessary Breaks + Replaces.  Otherwise,
			# clear the fields.
			if ($replaces) {
				push(@dbgsym_options, "-DReplaces=${replaces}",
					"-DBreaks=${replaces}");
			} else {
				push(@dbgsym_options, '-UReplaces', '-UBreaks');
			}
			install_dir("${dbgsym_tmp}/DEBIAN");
			doit("dpkg-gencontrol", "-p${package}", "-l$changelog", "-T$substvars",
				"-P${dbgsym_tmp}",@{$dh{U_PARAMS}}, @dbgsym_options);

			reset_perm_and_owner(0644, "${dbgsym_tmp}/DEBIAN/control");
		} elsif ($build_ids) {
			# Only include the build-id if there is no dbgsym package (if
			# there is a dbgsym package, the build-ids into the control
			# file of the dbgsym package)
			push(@debug_info_params, "-DBuild-Ids=${build_ids}");
		}

		# Remove explicit "Multi-Arch: no" headers to avoid autorejects by dak.
		push (@multiarch_params, '-UMulti-Arch')
			if (package_multiarch($package) eq 'no');

		# Generate and install control file.
		doit("dpkg-gencontrol", "-p$package", "-l$changelog", "-T$substvars",
			"-P$tmp", @debug_info_params, @multiarch_params,
			@{$dh{U_PARAMS}});

		# This chmod is only necessary if the user sets the umask to
		# something odd.
		reset_perm_and_owner(0644, "${tmp}/DEBIAN/control");
	}
};

sub read_dbgsym_file {
	my ($dbgsym_info_file, $dbgsym_info_dir) = @_;
	my $dbgsym_path = "${dbgsym_info_dir}/${dbgsym_info_file}";
	my $result;
	if (-f $dbgsym_path) {
		open(my $fd, '<', $dbgsym_path)
			or error("open $dbgsym_path failed: $!");
		chomp($result = <$fd>);
		$result =~ s/\s++$//;
		close($fd);
	}
	return $result;
}

sub read_dbgsym_migration {
	return read_dbgsym_file('dbgsym-migration', @_);
}

sub read_dbgsym_build_ids {
	my $res = read_dbgsym_file('dbgsym-build-ids', @_);
	my (%seen, @unique);
	return '' if not defined($res);
	for my $id (split(' ', $res)) {
		next if $seen{$id}++;
		push(@unique, $id);
	}
	return join(' ', @unique);
}


1;
