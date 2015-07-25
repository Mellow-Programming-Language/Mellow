
use strict;
use warnings;

use FindBin;
use Test::More;

my $scriptDir = "$FindBin::Bin";
my $binDir = "$scriptDir/../";
my $compiler = "$scriptDir/../compiler";
my $dummyFile = "TEST_RESULT_FILE";

# Test the examples in the examples directory
my $examplesDir = "$scriptDir/../examples/";
# Issue files in the compilation_issues directory
my $compilationDir = "$scriptDir/compilation_issues/";

opendir(DIR, "$examplesDir");
my @examplesFiles = grep {
    $_ =~ /^.+\.mlo$/
} readdir(DIR);
closedir(DIR);

opendir(DIR, "$compilationDir");
my @compilationFiles = grep {
    $_ =~ /^.+\.mlo$/
} readdir(DIR);
closedir(DIR);

@compilationFiles = sort @compilationFiles;

chdir($binDir);

unless (-x $compiler) {
    unless (system("make") == 0 && -x $compiler) {
        die "Failed to 'make' non-existing $compiler\n";
    }
}

foreach my $file (@examplesFiles) {
    ok(
        system("$compiler", "$examplesDir$file", "--o", $dummyFile) == 0,
        "Compiling: $file"
    );
}

foreach my $file (@compilationFiles) {
    # Read each file, scrape any of the comment codes, and perform the
    # regression test in each issue file
    open my $fh, '<', "$compilationDir$file"
        or die "Couldn't read file [$file]!";
    my @data = <$fh>;
    close $fh;
    my $directives = {};
    foreach my $line (@data) {
        if ($line =~ m|//\s*ISSUE:\s*([0-9]+)\s*$|) {
            $directives->{"ISSUE"} = $1;
        }
        elsif ($line =~ m|//\s*EXPECTS:\s*(.*)\s*$|) {
            $directives->{"EXPECTS"} = $1;
        }
    }
    foreach my $d (qw(ISSUE EXPECTS)) {
        if (!exists $directives->{$d}) {
            die "Missing directive: [$d]";
        }
    }
    my $expected = 0;
    $expected = 1 if ($directives->{"EXPECTS"} =~ /fail|failure|FAIL|FAILURE/);
    is(
        system(
            "$compiler $compilationDir$file --o $dummyFile 1>/dev/null 2>&1"
        ) >> 8, $expected,
        "Compiling: $file: Expects "
        . (($expected == 0) ? "success" : "failure")
    );
}

if (-e $dummyFile) {
    unlink $dummyFile;
}

chdir($scriptDir);

done_testing;
