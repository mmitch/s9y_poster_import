#!/usr/bin/perl
# $Id: s9y_poster_import.pl,v 1.2 2007-09-30 16:44:03 mitch Exp $
use strict;
use warnings;
use Time::Local;
use Data::Dumper;
use DBI;

my $posterdir = $ARGV[0];

die "needs poster data directory as first argument" unless defined $posterdir and $posterdir ne '';

# get database connection
my $dbh = DBI->connect(
		       'DBI:mysql:database=serendipity;host=localhost;port=3306',
		       'serendipity',
		       'ihego906',
		       {'PrintError' => 1,
			'PrintWarn' => 1,
			'ShowErrorStatement' => 1,
			    
			},
		       # {'RaiseError' => 1}
		       );

# use utf8
$dbh->do('SET NAMES utf8');

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
    ## TODO: localtime or gmtime??
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
	## TODO: localtime or gmtime??
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

	## TODO: localtime or gmtime??
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


##    next unless @{$entry{TRACKBACKS}} > 0 and @{$entry{COMMENTS}} > 0;

    # save entry
    my $insert_entry =
	sprintf('INSERT INTO serendipity_entries (title, timestamp, body, comments, trackbacks, author, authorid ) VALUES ( %s, %d, %s, %d, %d, %s, %d )',
		$dbh->quote($entry{TITLE}),
		$entry{TIMESTAMP} + 0,
		$dbh->quote($entry{BODY}),
		0,
		0,
		$dbh->quote($entry{AUTHOR}),
		1);

#    print "$insert_entry\n";
    $dbh->do($insert_entry);

    my $entryid = $dbh->last_insert_id(undef, undef, undef, undef);

    # save category
    if (exists $category{$entry{CATEGORY}}) {
	
	my $get_category =
	    $dbh->prepare('SELECT categoryid FROM serendipity_category WHERE category_name = '.$dbh->quote($category{$entry{CATEGORY}}));
	$get_category->execute();
	if (my $ref = $get_category->fetchrow_hashref()) {
	    my $insert_category =
		sprintf('INSERT INTO serendipity_entrycat (entryid, categoryid) VALUES ( %d, %d )', $entryid, $ref->{categoryid} + 0);
	    # print "$insert_category\n";
	    $dbh->do($insert_category);
	}
    }

    # save comments
    foreach my $comment (@{$entry{COMMENTS}}) {
	my $insert_comment =
	    sprintf('INSERT INTO serendipity_comments (entry_id, timestamp, author, url, body, type, status) VALUES ( %d, %d, %s, %s, %s, %s, %s )', 
		    $entryid,
		    $comment->{TIMESTAMP},
		    $dbh->quote($comment->{AUTHOR}),
		    exists $comment->{URL} ? $dbh->quote($comment->{URL}) : 'NULL',
		    $dbh->quote($comment->{BODY}),
		    $dbh->quote('NORMAL'),
		    $dbh->quote('pending'));
	# print "$insert_comment\n";
	$dbh->do($insert_comment);
    }

    # save trackbacks
    foreach my $trackback (@{$entry{TRACKBACKS}}) {
	my $insert_trackback =
	    sprintf('INSERT INTO serendipity_comments (entry_id, timestamp, author, url, body, type, status) VALUES ( %d, %d, %s, %s, %s, %s, %s )', 
		    $entryid,
		    $trackback->{TIMESTAMP},
		    $dbh->quote($trackback->{BLOG_NAME}),
		    exists $trackback->{URL} ? $dbh->quote($trackback->{URL}) : 'NULL',
		    $dbh->quote($trackback->{BODY}),
		    $dbh->quote('TRACKBACK'),
		    $dbh->quote('pending'));
	# print "$insert_trackback\n";
	$dbh->do($insert_trackback);
    }

##    exit;

}

__DATA__

# restore after test run

delete from serendipity_comments where entry_id != 1;
delete from serendipity_entries where id != 1;
delete from serendipity_entrycat where entryid != 1;
delete from serendipity_references where entry_id != 1;

