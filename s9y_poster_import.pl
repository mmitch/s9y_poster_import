#!/usr/bin/perl
# $Id: s9y_poster_import.pl,v 1.6 2007-10-06 12:17:23 mitch Exp $
use strict;
use warnings;
use Time::Local;
use Data::Dumper;
use DBI;

# this script imports a poster blog ( ) into Serendipity (www.s9y.org)
# it has been tested with poster 1.0.8 and s9y 
#
# 2007 (c) by Christian Garbs <mitch@cgarbs.de>
# licensed under GNU GPL v2
#
# USAGE:
# 
# 1. edit below to set up the database connection and your S9Y table prefix
# 2. run this script with the poster data directory as first argument

my $dbh = DBI->connect(
		       'DBI:mysql:database=serendipity;host=localhost;port=3306',
		       'serendipity',  # username
		       'ihego906',     # password
		       {'PrintError' => 1,
			'PrintWarn' => 1,
			'ShowErrorStatement' => 1,
			},
		       # {'RaiseError' => 1}
		       );

my $tableprefix = 'serendipity_';

# use utf8?
$dbh->do('SET NAMES utf8');

###################################################################################################

# process arguments
my $posterdir = $ARGV[0];
die "needs poster data directory as first argument" unless defined $posterdir and $posterdir ne '';

# global variables
my %mapping;

# read categories
my %category;
open CATEGORY, '<', "$posterdir/../categories" or die "can't open `$posterdir/../categories': $1";
while (my $line = <CATEGORY>) {
    my ($short, $name, undef) = split /:/, $line, 3;
    $category{$short} = $name;
}
close CATEGORY or die "can't open `$posterdir/../categories': $1";

# read entries
opendir ENTRY, $posterdir or die "can't opendir `$posterdir': $!";
my @entry = sort grep { -d "$posterdir/$_" and $_ =~ /^\d{14}$/ } readdir(ENTRY);
closedir ENTRY or die "can't closedir `$posterdir': $!";
print @entry . " entries found.\n";


# process entries
foreach my $entry (@entry) {
    print "entry $entry...\n";
    
    my $dir = "$posterdir/$entry";
    my $line;
    my %entry;
    
    # read comments
    opendir COMMENT, "$dir/comments/" or die "can't opendir `$dir/comments/': $!";
    my @comment = sort grep { -f "$dir/comments/$_" and $_ =~ /^\d{14}$/ } readdir(COMMENT);
    closedir COMMENT or die "can't closedir `$dir/comments/': $!";
    print "  " . @comment . " comments found.\n";

    # read trackbacks
    opendir TRACKBACK, "$dir/trackbacks/" or die "can't opendir `$dir/trackbacks/': $!";
    my @trackback = sort grep { -f "$dir/trackbacks/$_" and $_ =~ /^\d{14}$/ } readdir(TRACKBACK);
    closedir TRACKBACK or die "can't closedir `$dir/trackbacks/': $!";
    print "  " . @trackback . " trackbacks found.\n";

    # process entry
    $entry{TIMESTAMP} = timelocal(
			       substr($entry, 12, 2),
			       substr($entry, 10, 2),
			       substr($entry,  8, 2),
			       substr($entry,  6, 2),
			       substr($entry,  4, 2)-1,
			       substr($entry,  0, 4)
			       );

    open ENTRY, '<', "$dir/post" or die "can't open `$dir/post': $!";
    ## the first three lines contain administrative data (AUTHOR, CATEGORY, TITLE)
    for (1..3) {
	$line = <ENTRY>;
	chomp $line;
	if ($line =~ /^([A-Z_]+): (.*)$/) {
	    $entry{$1} = $2;
	}
    }
    while ($line = <ENTRY>) {
	chomp $line;
	$entry{BODY} .= $line .' ';
    }
    $entry{BODY} =~ s/\s+$//;
    close ENTRY or die "can't close `$dir/post': $!";

    # process comments
    $entry{COMMENTS} = [];
    foreach my $comment (sort @comment) {
	my %comment;
	$comment{TIMESTAMP} = timelocal(
				     substr($comment, 12, 2),
				     substr($comment, 10, 2),
				     substr($comment,  8, 2),
				     substr($comment,  6, 2),
				     substr($comment,  4, 2)-1,
				     substr($comment,  0, 4)
				     );

	open COMMENT, '<', "$dir/comments/$comment" or die "can't open `$dir/comments/$comment': $!";
	$line = <COMMENT>;
	chomp $line;
	if ($line =~ /^AUTHOR: (.*)$/) {
	    $line = $1;
	    if ($line =~ /^(.*?):(.*)$/) {
		$comment{AUTHOR} = $1;
		$comment{URL} = $2 unless $2 =~ m|^http\\://www.cgarbs.de/blog/index.php/|;
	    } else {
		$comment{AUTHOR} = $line;
	    }
	}
	while ($line = <COMMENT>) {
	    chomp $line;
	    $comment{BODY} .= $line .' ';
	}
	$comment{BODY} =~ s/\s+$//;
	close COMMENT or die "can't close `$dir/comments/$comment': $!";
	push @{$entry{COMMENTS}}, {%comment};
    }

    # process trackbacks
    $entry{TRACKBACKS} = [];
    foreach my $trackback (sort @trackback) {
	my %trackback;

	$trackback{TIMESTAMP} = timelocal(
				     substr($trackback, 12, 2),
				     substr($trackback, 10, 2),
				     substr($trackback,  8, 2),
				     substr($trackback,  6, 2),
				     substr($trackback,  4, 2)-1,
				     substr($trackback,  0, 4)
				     );

	open TRACKBACK, '<', "$dir/trackbacks/$trackback" or die "can't open `$dir/trackbacks/$trackback': $!";
	## the first three lines contain administrative data (URL, TITLE, BLOG_NAME)
	for (1..3) {
	    $line = <TRACKBACK>;
	    chomp $line;
	    if ($line =~ /^([A-Z_]+): (.*)$/) {
		$trackback{$1} = $2;
	    }
	}
	while ($line = <TRACKBACK>) {
	    chomp $line;
	    $trackback{BODY} .= $line .' ';
	}
	$trackback{BODY} =~ s/\s+$//;
	close TRACKBACK or die "can't close `$dir/trackbacks/$trackback': $!";
	push @{$entry{TRACKBACKS}}, {%trackback};
    }
    
    print "\n";
    
    # save entry
    my $insert_entry =
	sprintf('INSERT INTO %sentries (title, timestamp, body, comments, trackbacks, author, authorid ) VALUES ( %s, %d, %s, %d, %d, %s, %d )',
		$tableprefix,
		$dbh->quote($entry{TITLE}),
		$entry{TIMESTAMP} + 0,
		$dbh->quote($entry{BODY}),
		0,
		0,
		$dbh->quote($entry{AUTHOR}),
		1
		);
    
    $dbh->do($insert_entry);
    
    my $entryid = $dbh->last_insert_id(undef, undef, undef, undef);
    $mapping{$entry} = $entryid;
    
    # save category
    if (exists $category{$entry{CATEGORY}}) {
	
	my $get_category =
	    $dbh->prepare(sprintf('SELECT categoryid FROM %scategory WHERE category_name = %s',
				  $tableprefix,
				  $dbh->quote($category{$entry{CATEGORY}})
				  ));
	$get_category->execute();
	if (my $ref = $get_category->fetchrow_hashref()) {
	    my $insert_category =
		sprintf('INSERT INTO %sentrycat (entryid, categoryid) VALUES ( %d, %d )',
			$tableprefix,
			$entryid,
			$ref->{categoryid} + 0
			);
	    $dbh->do($insert_category);
	}
    }
    
    # save comments
    foreach my $comment (@{$entry{COMMENTS}}) {
	my $insert_comment =
	    sprintf('INSERT INTO %scomments (entry_id, timestamp, author, url, body, type, status) VALUES ( %d, %d, %s, %s, %s, %s, %s )', 
		    $tableprefix,
		    $entryid,
		    $comment->{TIMESTAMP},
		    $dbh->quote($comment->{AUTHOR}),
		    exists $comment->{URL} ? $dbh->quote($comment->{URL}) : 'NULL',
		    $dbh->quote($comment->{BODY}),
		    $dbh->quote('NORMAL'),
		    $dbh->quote('pending')
		    );
	$dbh->do($insert_comment);
    }

    # save trackbacks
    foreach my $trackback (@{$entry{TRACKBACKS}}) {
	my $insert_trackback =
	    sprintf('INSERT INTO %scomments (entry_id, timestamp, author, url, body, type, status) VALUES ( %d, %d, %s, %s, %s, %s, %s )',
		    $tableprefix,
 		    $entryid,
		    $trackback->{TIMESTAMP},
		    $dbh->quote($trackback->{BLOG_NAME}),
		    exists $trackback->{URL} ? $dbh->quote($trackback->{URL}) : 'NULL',
		    $dbh->quote($trackback->{BODY}),
		    $dbh->quote('TRACKBACK'),
		    $dbh->quote('pending')
		    );
	$dbh->do($insert_trackback);
    }
	
}
    
# print mapping
print "\nmapped entries:\n";
print "$_ $mapping{$_}\n" foreach (sort keys %mapping);

__DATA__

# SQL to delete imports after test run
# (I want to keep my entry 1, it's a real test entry that's not imported from poster)
delete from serendipity_comments where entry_id != 1;
delete from serendipity_entries where id != 1;
delete from serendipity_entrycat where entryid != 1;
delete from serendipity_references where entry_id != 1;

