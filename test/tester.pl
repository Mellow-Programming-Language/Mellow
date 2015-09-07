
use strict;
use warnings;

use FindBin;
use Test::More;
use Getopt::Long;

my $compiler_exe = "compiler";
my $issueDir;

GetOptions (
    "compiler=s" => \$compiler_exe,
    "issuedir=s" => \$issueDir,
);

unless ($issueDir) {
    die "Must pass a --issuedir argument to testing script";
}

my $scriptDir = "$FindBin::Bin";
my $binDir = "$scriptDir/../";
my $compiler = "$scriptDir/../$compiler_exe";
my $dummyFile = "TEST_RESULT_FILE";

# Regression test the files in the $issueDir directory
my $execRegressDir = "$binDir/$issueDir/";

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

sub testsub {
    my (
        $compiler, $execRegressDir, $file, $issueDir, $directives,
    ) = @_;
    return sub {
        my $continue = 1;
        my $want_fail = 0;
        if ($continue) {
            my $res = system(
                "$compiler $execRegressDir$file --o $dummyFile >/dev/null 2>&1"
            );
            my $tester = sub {
                my ($res) = @_;
                return $res == 0;
            };
            if (exists $directives->{'COMPILES'}
                && $directives->{'COMPILES'} =~ /no|fails|failure|false/i) {
                $want_fail = 1;
                # We need this so perl doesn't think we want to recurse on the
                # anonymous code-ref
                my $oldtester = $tester;
                $tester = sub {
                    my ($res) = @_;
                    return !$oldtester->($res);
                };
            }
            $continue = ok(
                $tester->($res),
                "Compiling: $issueDir/$file: [$res]"
            );
            if ($want_fail
                || (
                    exists $directives->{'NO_EXEC'}
                    && $directives->{'NO_EXEC'} =~ /true|yes/i
                )
            ) {
                $continue = 0;
            }
        }
        if ($continue) {
            my $res = system(
                "$binDir$dummyFile >/dev/null 2>&1"
            );
            my $tester = sub {
                my ($ret_code, $signal) = @_;
                return $ret_code == 0 && $signal == 0;
            };
            if (exists $directives->{'SHOULD'}
                && $directives->{'SHOULD'} =~ /fail|break/i) {
                $want_fail = 1;
                # We need this so perl doesn't think we want to recurse on the
                # anonymous code-ref
                my $oldtester = $tester;
                $tester = sub {
                    my ($ret_code, $signal) = @_;
                    return !$oldtester->($ret_code, $signal);
                };
            }
            my $ret_code = $res & 127;
            my $signal = ($res >> 8) & 127;
            $continue = ok(
                $tester->($ret_code, $signal),
                "Executing: $issueDir/$file: [$ret_code] [$signal]"
            );
            $continue = 0 if $want_fail;
        }
        if ($continue
            && (
                !exists $directives->{'NO_OUTPUT'}
                || $directives->{'NO_OUTPUT'} !~ /true|yes/i
            )
        ) {
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

sub processDirectives {
    my (@data) = @_;
    my $directives = {};
    foreach my $line (@data) {
        if ($line =~ m|//\s*EXPECTS:\s*"(.*)"\s*$|) {
            $directives->{'EXPECTS'} = $1;
        }
        elsif ($line =~ m|//\s*ISSUE:\s*(.*)\s*$|) {
            $directives->{'ISSUE'} = $1;
        }
        elsif ($line =~ m|//\s*STATUS:\s*(.*)\s*$|) {
            $directives->{'STATUS'} = $1;
        }
        elsif ($line =~ m|//\s*NO_OUTPUT:\s*(.*)\s*$|) {
            $directives->{'NO_OUTPUT'} = $1;
        }
        elsif ($line =~ m|//\s*SHOULD:\s*(.*)\s*$|) {
            $directives->{'SHOULD'} = $1;
        }
        elsif ($line =~ m|//\s*COMPILES:\s*(.*)\s*$|) {
            $directives->{'COMPILES'} = $1;
        }
        elsif ($line =~ m|//\s*NO_EXEC:\s*(.*)\s*$|) {
            $directives->{'NO_EXEC'} = $1;
        }
    }
    # No directives were passed, so we assume the default case of:
    # "We expect this to compile, but don't continue beyond that"
    if (scalar keys %$directives == 0) {
        $directives->{'COMPILES'} = "yes";
        $directives->{'NO_EXEC'} = "yes";
        $directives->{'NO_OUTPUT'} = "yes";
        $directives->{'ISSUE'} = "Simple compilation test";
    }
    if (!exists $directives->{'NO_OUTPUT'}
        || $directives->{'NO_OUTPUT'} !~ /true|yes/i)
    {
        unless (exists $directives->{'EXPECTS'}) {
            die "Must have EXPECTS directive when NO_OUTPUT isn't specified";
        }
    }
    return $directives;
}

foreach my $file (@files) {
    # Read each file, scrape any of the comment codes, and perform the
    # regression test in each issue file
    open my $fh, '<', "$execRegressDir$file"
        or die "Couldn't read file [$file]!";
    my @data = <$fh>;
    close $fh;
    my $directives = processDirectives(@data);
    my $issueString;
    if (exists $directives->{'ISSUE'}) {
        $issueString = $directives->{"ISSUE"};
    }
    else {
        $issueString = "Generic issue";
    }
    if (!exists $directives->{'STATUS'} || $directives->{'STATUS'} !~ /todo/i) {
        subtest $issueString => testsub(
            $compiler, $execRegressDir, $file, $issueDir, $directives,
        );
    }
    elsif (exists $directives->{'STATUS'}
        && $directives->{'STATUS'} =~ /todo/i)
    {
        TODO: {
            local $TODO = "Not yet fixed/implemented";
            subtest $issueString => testsub(
                $compiler, $execRegressDir, $file, $issueDir, $directives,
            );
        }
    }
}

if (-e $dummyFile) {
    unlink $dummyFile;
}

done_testing;
