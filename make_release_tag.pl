#!/usr/bin/env perl
use strict;
use warnings;

use Carp;
use Data::Dumper;
use FindBin;
use File::Spec;
use Getopt::Std;
use List::Util qw/ min /;
use Pod::Usage;
use version;

# parse and validate command line args
my %opt;

sub vprint(@) {
  print @_ if $opt{v};
  @_;
}
sub fsystem(@) {
    my $cmd_string = join(' ', map {$_ =~ /\s/ ? "'$_'" : $_} @_);

    print "DO: $cmd_string\n" if $opt{v} || $opt{x};
    unless($opt{x}) {
        system(@_);
        $? and die "command failed: $cmd_string\nAborting.\n";
    }
}

getopts('nMmr:V:vpx',\%opt) or pod2usage(1);

$opt{M} || $opt{m} || $opt{V}
    or pod2usage('must specify either -M, -m, or -V');
@ARGV == 1 || @ARGV == 2 or pod2usage('must provide component name, and optionally remote name');

my ($component_name,$remote) = @ARGV;
$remote = 'origin' unless defined $remote;

unless( $opt{n} ) {
    vprint("fetching tags from $remote ...\n");
    fsystem('git','fetch','--tags',
            ($opt{v} ? () : '-q'),
            $remote )
}

my @previous_releases = previous_releases($component_name);

#figure out the next major version number
my $major_version =
  defined( $opt{V} ) ? $opt{V} :
  @previous_releases ? $opt{M} ? $previous_releases[0][0]+1 :
                       $opt{m} ? $previous_releases[0][0]   :
                       pod2usage('must specify either -M, -m, or -V')
                     : 1
  ;

#figure out the next minor version number
my $minor_version = do {
  if(my @other_rels = grep {$major_version == $_->[0]} @previous_releases) {
    $other_rels[0][1] + 1
  } else {
    0
  }
};

my $release_ref      = $opt{r} || 'master';
my $new_release_tag  = "$component_name-$major_version.$minor_version";

fsystem( 'git', 'tag',
         -m => "$FindBin::Script: tagging $release_ref as release $new_release_tag",
         $new_release_tag,
         $release_ref,
        );

print <<"";
tagged $release_ref as release $new_release_tag


if( $opt{p} ) {
    vprint("pushing tags to $remote ...\n");
    fsystem(qw( git push --tags ),
            ($opt{v} ? () : '-q'),
            $remote );
}


exit;

#### SUBROUTINES

# args: git remote base, component name (e.g. 'cxgn-corelibs')
# returns: a list as ([major,minor],[major,minor]) of
# previous revisions that are present in the repos,
# in descending order by major and minor revision number
sub previous_releases {
    my ($component_name) = @_;

    my @releases = 
        sort { $b->[0] <=> $a->[0] || $b->[1] <=> $a->[1] }
        map  {
            if(m|^$component_name-(\d+)\.(\d+)(?=\s)|) {
                [$1,$2,$&]
            } else {
                ()
            }
        } `git tag`;

    vprint("last few $component_name releases:\n");
    vprint("  $_->[2]\n") for reverse grep $_, @releases[0 .. min(2,$#releases)];
    return @releases;
}

sub revparse {
    my $r = shift;
    $r = `git rev-parse $r`;
    chomp $r;
    return $r;
}

sub version_number {
    my $class = shift;
    my $tag = shift;
    $tag =~ /(v?[\d\.]+)$/
        or return;
    return version->new($1);
}

__END__

=head1 NAME

make_release_tag.pl -  make a new release tag for the given software component name.

=head1 SYNOPSIS

  cd my_component; make_release_tag.pl [options] my_component [ remote_name ]

  Must specify one of -M, -m, or -V.  Must be run from a working
  directory inside the git repository in question.

  Options:

  -n
     do not run 'git fetch --tags' before making a new release tag.
     good for making a tag without network access, but be sure someone
     has not already done it!

  -p
     run a git push --tags <remote> after creating the tag to push the
     tag to the given remote.  be careful with this!

  -M
     make this a major release.  equivalent to '-V <num+1>', where
     num is the current major release.

  -m
     number this as a minor release.  equivalent to '-V <num>', where
     num is the current major release.

  -r <sha or branch>
     the rev (branch, commit, or other tag) to take as this release,
     defaults to 'master'

  -V <num>
     major version number for this release, like '4'
     defaults to the next major number in the sequence
     of releases

  -v be verbose about what you're doing

  -x just do a dry run, printing what you _would_ do

=head1 EXAMPLES

=head2 Without autopush

=head3 make a new release tag for the Phenome component

  cd Phenome;  make_release_tag.pl -M Phenome

=head3 make sure the tag it just made is correct, then send it to github

  git push --tags

=head2 With autopush (be careful!)

  cd Phenome;  make_release_tag.pl -pM Phenome

=head1 AUTHOR

Robert Buels, E<lt>rmb32@cornell.eduE<gt>

=head1 COPYRIGHT & LICENSE

Copyright 2010 Boyce Thompson Institute for Plant Research

This program is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
