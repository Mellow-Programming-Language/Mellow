
use strict;
use warnings;

use FindBin;
use Test::More;

my $scriptDir = "$FindBin::Bin";
my $binDir = "$scriptDir/../";
my $compiler = "$scriptDir/../compiler";
my $dummyFile = "TEST_RESULT_FILE";

# Regression test the files in the execution_issues directory
my $execRegressDir = "$scriptDir/execution_issues/";

opendir(DIR, "$execRegressDir");
my @executableFiles = grep {
    $_ =~ /^.+\.mlo$/
} readdir(DIR);
closedir(DIR);

@executableFiles = sort @executableFiles;

chdir($binDir);

unless (-x $compiler) {
    unless (system("make") == 0 && -x $compiler) {
        die "Failed to 'make' non-existing $compiler\n";
    }
}

foreach my $file (@executableFiles) {
    # Read each file, scrape any of the comment codes, and perform the
    # regression test in each issue file
    open my $fh, '<', "$execRegressDir$file"
        or die "Couldn't read file [$file]!";
    my @data = <$fh>;
    close $fh;
    my $directives = {};
    foreach my $line (@data) {
        if ($line =~ m|//\s*ISSUE:\s*([0-9]+)\s*$|) {
            $directives->{"ISSUE"} = $1;
        }
        elsif ($line =~ m|//\s*EXPECTS:\s*"(.*)"\s*$|) {
            $directives->{"EXPECTS"} = $1;
        }
    }
    foreach my $d (qw(ISSUE EXPECTS)) {
        if (!exists $directives->{$d}) {
            die "Missing directive: [$d]";
        }
    }
    my $issueString = "Issue " . $directives->{"ISSUE"};
    subtest $issueString => sub {
        plan tests => 2;
        ok(
            system("$compiler", "$execRegressDir$file", "--o", $dummyFile) == 0,
            "Compiling: test/execution_issues/$file"
        );
        my $output = `$binDir$dummyFile`;
        chomp $output;
        is(
            $output, $directives->{"EXPECTS"},
            "Output matched"
        );
    };
}

if (-e $dummyFile) {
    unlink $dummyFile;
}

done_testing;
