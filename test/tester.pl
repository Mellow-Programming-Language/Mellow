
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

my $testnotes = {
    'MULTI_NORUN' => [],
    'SINGLE_NORUN' => [],
};

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
        my $input = "";
        if (exists $directives->{'INPUT'}) {
            $input = " printf '$directives->{'INPUT'}' | ";
        }
        if ($continue) {
            my $options = "";
            if (exists $directives->{'COMPILE_OPTIONS'}) {
                $options = join " ", (
                    map {
                        "--$_"
                    } (split /\s/, $directives->{'COMPILE_OPTIONS'})
                );
            }
            my $res = system(
                "$compiler $options $execRegressDir$file "
                . "--o $dummyFile >/dev/null 2>&1"
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
            elsif (exists $directives->{'DONT_RUN_FOR'}) {
                if ($directives->{'DONT_RUN_FOR'} =~ /multi/i
                    && $compiler_exe =~ /multi/i) {
                    $continue = 0;
                    push @{$testnotes->{'MULTI_NORUN'}}, $file;
                }
                elsif ($directives->{'DONT_RUN_FOR'} !~ /multi/i
                    && $compiler_exe !~ /multi/i) {
                    $continue = 0;
                    push @{$testnotes->{'SINGLE_NORUN'}}, $file;
                }
            }
        }
        if ($continue) {
            my $res = system(
                "$input $binDir$dummyFile >/dev/null 2>&1"
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
            my $output = `$input $binDir$dummyFile`;
            if (exists $directives->{'EXPECTS'}) {
                chomp $output;
                $continue = is(
                    $output, $directives->{"EXPECTS"},
                    "Output matched"
                );
            }
            elsif (exists $directives->{'EXPECTS_UNORDERED'}) {
                my $lines_set = {
                    map {
                        $_ => 1
                    } (split "\n", $output)
                };
                my $expected_set = {
                    map {
                        $_ => 1
                    } (@{$directives->{'EXPECTS_UNORDERED'}})
                };
                $continue = is_deeply(
                    $lines_set, $expected_set,
                    "Output matched"
                );
            }
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
        elsif ($line =~ m|//\s*EXPECTS_UNORDERED:|) {
            $line =~ s|//\s*EXPECTS_UNORDERED:\s*||;
            my $unordered_lines = [];
            foreach ($line =~ m|"(.*?)"|g) {
                push @$unordered_lines, $_;
            }
            $directives->{'EXPECTS_UNORDERED'} = $unordered_lines;
        }
        if ($line =~ m|//\s*INPUT:\s*"(.*)"\s*$|) {
            $directives->{'INPUT'} = $1;
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
        elsif ($line =~ m|//\s*COMPILE_OPTIONS:\s*(.*)\s*$|) {
            $directives->{'COMPILE_OPTIONS'} = $1;
        }
        elsif ($line =~ m|//\s*DONT_RUN_FOR:\s*(.*)\s*$|) {
            $directives->{'DONT_RUN_FOR'} = $1;
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
        unless (exists $directives->{'EXPECTS'}
            || exists $directives->{'EXPECTS_UNORDERED'}) {
            die "Must have EXPECTS directive when NO_OUTPUT isn't specified";
        }
    }
    if (exists $directives->{'EXPECTS'}
        && exists $directives->{'EXPECTS_UNORDERED'}) {
        die "Cannot have both 'EXPECTS' and 'EXPECTS_UNORDERED'";
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

if (@{$testnotes->{'MULTI_NORUN'}}) {
    print "-" x 78 . "\n";
    print "NOTE: Multithreaded runtime:\n";
    print "  Skipped exec tests for:\n";
    foreach my $file (@{$testnotes->{'MULTI_NORUN'}}) {
        print "    $file\n";
    }
    print "-" x 78 . "\n";
}
if (@{$testnotes->{'SINGLE_NORUN'}}) {
    print "-" x 78 . "\n";
    print "NOTE: Singlethreaded runtime:\n";
    print "  Skipped exec tests for:\n";
    foreach my $file (@{$testnotes->{'SINGLE_NORUN'}}) {
        print "    $file\n";
    }
    print "-" x 78 . "\n";
}

done_testing;
