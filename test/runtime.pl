
use strict;
use warnings;

use FindBin;
use Test::More;

my $compiler_exe = "compiler";
if (@ARGV) {
    $compiler_exe = shift @ARGV;
}

my $scriptDir = "$FindBin::Bin";
my $binDir = "$scriptDir/../";
my $compiler = "$scriptDir/../$compiler_exe";
my $dummyFile = "TEST_RESULT_FILE";

my $issueDir = 'runtime_issues';
# Regression test the files in the $issueDir directory
my $execRegressDir = "$scriptDir/$issueDir/";

opendir(DIR, "$execRegressDir");
my @files = grep {
    $_ =~ /^.+\.mlo$/
} readdir(DIR);
closedir(DIR);

@files = sort @files;

chdir($binDir);

unless (-x $compiler) {
    die "'$compiler' does not exist.\n";
}

foreach my $file (@files) {
    # Read each file, scrape any of the comment codes, and perform the
    # regression test in each issue file
    open my $fh, '<', "$execRegressDir$file"
        or die "Couldn't read file [$file]!";
    my @data = <$fh>;
    close $fh;
    my $directives = {};
    foreach my $line (@data) {
        if ($line =~ m|//\s*EXPECTS:\s*"(.*)"\s*$|) {
            $directives->{"EXPECTS"} = $1;
        }
        elsif ($line =~ m|//\s*ISSUE:\s*(.*)\s*$|) {
            $directives->{'ISSUE'} = $1;
        }
        elsif ($line =~ m|//\s*STATUS:\s*(.*)\s*$|) {
            $directives->{'STATUS'} = $1;
        }
    }
    foreach my $d (qw(EXPECTS)) {
        if (!exists $directives->{$d}) {
            die "Missing directive: [$d]";
        }
    }
    my $issueString;
    if (exists $directives->{'ISSUE'}) {
        $issueString = $directives->{"ISSUE"};
    }
    else {
        $issueString = "Generic issue";
    }
    if (!exists $directives->{'STATUS'} || $directives->{'STATUS'} !~ /todo/i) {
        subtest $issueString => sub {
            my $continue = ok(
                system(
                    "$compiler", "$execRegressDir$file", "--o", $dummyFile
                ) == 0,
                "Compiling: test/$issueDir/$file"
            );
            if ($continue) {
                my $res = system(
                    "$binDir$dummyFile >/dev/null 2>&1"
                );
                my $ret_code = $res & 127;
                my $signal = ($res >> 8) & 127;
                $continue = ok(
                    $ret_code == 0 && $signal == 0,
                    "Executing: test/$issueDir/$file: [$ret_code] [$signal]"
                );
            }
            if ($continue) {
                my $output = `$binDir$dummyFile`;
                chomp $output;
                $continue = is(
                    $output, $directives->{"EXPECTS"},
                    "Output matched"
                );
            }
            done_testing;
        };
    }
    elsif (exists $directives->{'STATUS'} 
        && $directives->{'STATUS'} =~ /todo/i) 
    {
        TODO: {
            local $TODO = "Not yet fixed/implemented";
            subtest $issueString => sub {
                my $continue = ok(
                    system(
                        "$compiler", "$execRegressDir$file", "--o", $dummyFile
                    ) == 0,
                    "Compiling: test/$issueDir/$file"
                );
                if ($continue) {
                    my $res = system(
                        "$binDir$dummyFile >/dev/null 2>&1"
                    );
                    my $ret_code = $res & 127;
                    my $signal = ($res >> 8) & 127;
                    $continue = ok(
                        $ret_code == 0 && $signal == 0,
                        "Executing: test/$issueDir/$file: [$ret_code] [$signal]"
                    );
                }
                if ($continue) {
                    my $output = `$binDir$dummyFile`;
                    chomp $output;
                    $continue = is(
                        $output, $directives->{"EXPECTS"},
                        "Output matched"
                    );
                }
                done_testing;
            };
        }
    }
}

if (-e $dummyFile) {
    unlink $dummyFile;
}

done_testing;
