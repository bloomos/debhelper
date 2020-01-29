package Debian::Debhelper::Commands::dh_compress;
use strict;
use warnings;

use Cwd qw(getcwd abs_path);
use File::Spec::Functions qw(abs2rel);
use Debian::Debhelper::Dh_Lib;

sub process_packages_in_parallel {
	my $olddir;

	foreach my $package (@_) {
		my $tmp=tmpdir($package);

		my $compress=pkgfile($package,"compress");

		# Run the file name gathering commands from within the directory
		# structure that will be effected.
		next unless -d $tmp;
		my $ignore_doc_dirs = '-name _sources';
		if (not compat(11)) {
			my $target_package = compute_doc_main_package($package);
			$ignore_doc_dirs .= qq{ -o -path "usr/share/doc/${package}/examples"};
			$ignore_doc_dirs .= qq{ -o -path "usr/share/doc/${target_package}/examples"}
				if $target_package and $target_package ne $package;
		}
		$olddir = getcwd() if not defined $olddir;
		verbose_print("cd $tmp");
		chdir($tmp) || error("Can't cd to $tmp: $!");

		# Figure out what files to compress.
		my @files;
		# First of all, deal with any files specified right on the command line.
		if (($package eq $dh{FIRSTPACKAGE} || $dh{PARAMS_ALL}) && @ARGV) {
			push @files, map { s{^/+}{}; $_ } @ARGV;
		}
		if ($compress) {
			# The compress file is a sh script that outputs the files to be compressed
			# (typically using find).
			warning("$compress is deprecated; use -X or avoid calling dh_compress instead");
			push @files, split(/\n/,`sh $olddir/$compress 2>/dev/null`);
		} else {
			# Note that all the excludes of odd things like _z
			# are because gzip refuses to compress such files, assuming
			# they are zip files. I looked at the gzip source to get the
			# complete list of such extensions: ".gz", ".z", ".taz",
			# ".tgz", "-gz", "-z", "_z"
			push @files, split(/\n/,`
				find usr/share/info usr/share/man -type f ! -iname "*.gz" \\
					! -iname "*.gif" ! -iname "*.png" ! -iname "*.jpg" \\
					! -iname "*.jpeg" \\
					2>/dev/null || true;
				find usr/share/doc \\
					\\( -type d \\( $ignore_doc_dirs \\) -prune -false \\) -o \\
					-type f \\( -size +4k -o -name "changelog*" -o -name "NEWS*" \\) \\
					\\( -name changelog.html -o ! -iname "*.htm*" \\) \\
					! -iname "*.xhtml" \\
					! -iname "*.gif" ! -iname "*.png" ! -iname "*.jpg" \\
					! -iname "*.jpeg" ! -iname "*.gz" ! -iname "*.taz" \\
					! -iname "*.tgz" ! -iname "*.z" ! -iname "*.bz2" \\
					! -iname "*-gz"  ! -iname "*-z" ! -iname "*_z" \\
					! -iname "*.epub" ! -iname "*.jar" ! -iname "*.zip" \\
					! -iname "*.odg" ! -iname "*.odp" ! -iname "*.odt" \\
					! -iname ".htaccess" ! -iname "*.css" \\
					! -iname "*.xz" ! -iname "*.lz" ! -iname "*.lzma" \\
					! -iname "*.haddock" ! -iname "*.hs" \\
					! -iname "*.svg" ! -iname "*.svgz" ! -iname "*.js" \\
					! -name "index.sgml" ! -name "objects.inv" ! -name "*.map" \\
					! -name "*.devhelp2" ! -name "search_index.json" \\
					! -name "copyright" 2>/dev/null || true;
				find usr/share/fonts/X11 -type f -name "*.pcf" 2>/dev/null || true;
			`);
		}

		# Exclude files from compression.
		if (@files && defined($dh{EXCLUDE}) && $dh{EXCLUDE}) {
			my @new = grep { not excludefile($_) } @files;
			@files=@new;
		}

		# Look for files with hard links. If we are going to compress both,
		# we can preserve the hard link across the compression and save
		# space in the end.
		my ($unique_files, $hardlinks) = find_hardlinks(@files);
		my @f = @{$unique_files};

		# normalize file names and remove duplicates
		my $norm_from_dir = $tmp;
		if ($norm_from_dir !~ m{^/}) {
			$norm_from_dir = "${olddir}/${tmp}";
		}
		my $resolved = abs_path($norm_from_dir)
			or error("Cannot resolve $norm_from_dir: $!");
		my @normalized = normalize_paths($norm_from_dir, $resolved, $tmp, @f);
		my %uniq_f; @uniq_f{@normalized} = ();
		@f = sort keys %uniq_f;

		# do it
		if (@f) {
			# Make executables not be anymore.
			xargs(\@f,"chmod","a-x");
			xargs(\@f,"gzip","-9nf");
		}

		# Now change over any files we can that used to be hard links so
		# they are again.
		foreach (keys %{$hardlinks}) {
			# Remove old file.
			rm_files($_);
			# Make new hardlink.
			doit("ln", "-f", "$hardlinks->{$_}.gz", "$_.gz");
		}

		verbose_print("cd '$olddir'");
		chdir($olddir);

		# Fix up symlinks that were pointing to the uncompressed files.
		my %links = map { chomp; $_ => 1 } qx_cmd('find', $tmp, '-type', 'l');
		my $changed;
		# Keep looping through looking for broken links until no more
		# changes are made. This is done in case there are links pointing
		# to links, pointing to compressed files.
		do {
			$changed = 0;
			foreach my $link (keys %links) {
				my ($directory) = $link =~ m:(.*)/:;
				my $linkval = readlink($link);
				if (! -e "$directory/$linkval" && -e "$directory/$linkval.gz") {
					# Avoid duplicate ".gz.gz" if the link already has
					# the .gz extension.  This can happen via
					# dh_installman when the .so is already compressed
					# and then dh_installman reencodes the target
					# manpage.
					my $link_name = $link;
					$link_name .= '.gz' if $link_name !~ m/[.]gz$/;
					rm_files($link, "$link.gz");
					make_symlink_raw_target("$linkval.gz", $link_name);
					delete $links{$link};
					$changed++;
				}
			}
		} while $changed;
	}
};

sub normalize_paths {
	my ($cwd, $cwd_resolved, $tmp, @paths) = @_;
	my @normalized;
	my $prefix = qr{\Q${tmp}/};

	for my $path (@paths) {
		my $abs = abs_path($path);
		if (not defined($abs)) {
			my $err = $!;
			my $alt = $path;
			if ($alt =~ s/^$prefix//) {
				$abs = abs_path($alt);
			}
			error(qq{Cannot resolve "$path": $err (relative to "${cwd}")})
				if (not defined($abs));
			warning(qq{Interpreted "$path" as "$alt"});
		}
		error("${abs} does not exist") if not -e $abs;
		push(@normalized, abs2rel($abs, $cwd_resolved));
	}
	return @normalized;
}

1;
