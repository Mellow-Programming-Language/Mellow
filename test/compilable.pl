
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

opendir(DIR, "$examplesDir");
my @examplesFiles = grep {
    $_ =~ /^.+\.mlo$/
} readdir(DIR);
closedir(DIR);

unless (-x $compiler) {
    chdir($binDir);
    unless (system("make") == 0 && -x $compiler) {
        die "Failed to 'make' non-existing $compiler\n";
    }
    chdir($scriptDir);
}

foreach my $file (@examplesFiles) {
    ok(
        system("$compiler", "$examplesDir$file", "--o", $dummyFile) == 0,
        "Compiling: $file"
    );
}

if (-e $dummyFile) {
    unlink $dummyFile;
}

done_testing;
