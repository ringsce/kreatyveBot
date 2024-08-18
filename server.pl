#!/usr/bin/perl

use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use Net::DNS;
use IO::Socket::INET6;
use IO::Socket::SSL;

# Server Configuration
my $use_ssl = 1;  # Set to 0 to disable SSL
my $server_port = 6667;
my $server_name = 'localhostd';
my %channels;

# Client storage
my %clients;
my $select = IO::Select->new();

# Create a listening socket
my $server_socket;

if ($use_ssl) {
    $server_socket = IO::Socket::SSL->new(
        LocalPort     => $server_port,
        Proto         => 'tcp',
        Listen        => 10,
        ReuseAddr     => 1,
        SSL_cert_file => 'server-cert.pem',
        SSL_key_file  => 'server-key.pem',
        SSL_version   => 'TLSv1_2',
        SSL_cipher_list => 'HIGH:!aNULL:!MD5',
        Domain        => AF_INET6
    ) or die "Couldn't open SSL socket on port $server_port: $!";
} else {
    $server_socket = IO::Socket::INET6->new(
        LocalPort => $server_port,
        Proto     => 'tcp',
        Listen    => 10,
        ReuseAddr => 1,
        Domain    => AF_INET6
    ) or die "Couldn't open socket on port $server_port: $!";
}

$select->add($server_socket);
print "IRC Server started on port $server_port\n";

while (1) {
    my @ready = $select->can_read();
    
    foreach my $socket (@ready) {
        if ($socket == $server_socket) {
            my $client_socket = $server_socket->accept();
            
            if ($use_ssl && !$client_socket->isa("IO::Socket::SSL")) {
                print "Failed SSL handshake with client.\n";
                next;
            }

            my $client_address = $client_socket->peerhost();
            my $client_port = $client_socket->peerport();
            
            print "Accepted new client from $client_address:$client_port\n";
            
            $clients{$client_socket} = {
                socket   => $client_socket,
                address  => $client_address,
                port     => $client_port,
                nick     => undef,
                user     => undef,
                realname => undef,
                channels => [],
            };
            
            $select->add($client_socket);
        } else {
            handle_client($socket);
        }
    }
}

sub handle_client {
    my $client_socket = shift;
    my $client_info = $clients{$client_socket};
    
    while (my $line = <$client_socket>) {
        chomp $line;

        # Print incoming command for debugging
        print "Received: $line\n";
        
        if ($line =~ /^NICK\s+(\S+)/) {
            my $nick = $1;
            $client_info->{nick} = $nick;
            print $client_socket ":$server_name 001 $nick :Welcome to $server_name, $nick\n";
        } elsif ($line =~ /^USER\s+(\S+)\s+\S+\s+\S+\s+:(.*)/) {
            my $user = $1;
            my $realname = $2;
            $client_info->{user} = $user;
            $client_info->{realname} = $realname;
        } elsif ($line =~ /^JOIN\s+(#\S+)/) {
            my $channel = $1;
            push @{$client_info->{channels}}, $channel;
            $channels{$channel}->{$client_socket} = $client_info->{nick};
            print $client_socket ":$server_name 332 $client_info->{nick} $channel :Welcome to $channel\n";
        } elsif ($line =~ /^PART\s+(#\S+)/) {
            my $channel = $1;
            delete $channels{$channel}->{$client_socket};
            @{$client_info->{channels}} = grep { $_ ne $channel } @{$client_info->{channels}};
            print $client_socket ":$server_name PART $channel :Leaving channel\n";
        } elsif ($line =~ /^PRIVMSG\s+(\S+)\s+:(.*)/) {
            my $target = $1;
            my $message = $2;
            foreach my $client_socket (keys %clients) {
                next if $client_socket eq $client_socket;
                if (exists $channels{$target}->{$client_socket}) {
                    #print $clients{$client_socket}->{socket} ":$client_info->{nick}!$client_info->{user}\@$client_info->{address} PRIVMSG $target :$message\n";
                }
            }
        } elsif ($line =~ /^TOPIC\s+(#\S+)\s+:(.*)/) {
            my $channel = $1;
            my $topic = $2;
            $channels{$channel}->{topic} = $topic;
            foreach my $client_socket (keys %clients) {
                if (exists $channels{$channel}->{$client_socket}) {
                    #print $clients{$client_socket}->{socket} ":$server_name TOPIC $channel :$topic\n";
                }
            }
        } elsif ($line =~ /^PING\s+(.*)/) {
            print $client_socket "PONG $1\n";
        } elsif ($line =~ /^WHOIS\s+(\S+)/) {
            my $nick = $1;
            foreach my $client_socket (keys %clients) {
                if ($clients{$client_socket}->{nick} eq $nick) {
                    #print $client_socket ":$server_name 311 $clients{$client_socket}->{nick} $nick $clients{$client_socket}->{user} $clients{$client_socket}->{address} * :$clients{$client_socket}->{realname}\n";
                    last;
                }
            }
        } elsif ($line =~ /^DNSLOOKUP\s+(\S+)/) {
            my $host = $1;
            my $resolver = Net::DNS::Resolver->new;
            my $query = $resolver->search($host);
            my $response = "No DNS record found.";
            if ($query) {
                $response = join(', ', map { $_->address } $query->answer);
            }
            print $client_socket "PRIVMSG $client_info->{nick} :$response\n";
        } elsif ($line =~ /^DCC\s+SEND\s+(\S+)\s+(\S+)/) {
            my ($file_path, $file_size) = ($1, $2);
            if (-e $file_path) {
                open my $file, '<', $file_path or next;
                my $file_data = do { local $/; <$file> };
                close $file;
                my @chunks = unpack("(A4096)*", $file_data);
                my $file_count = 0;
                foreach my $chunk (@chunks) {
                    last if $file_count >= 4;
                    print $client_socket "DCC SEND $file_path $file_size\n";
                    print $client_socket $chunk;
                    $file_count++;
                }
            } else {
                print $client_socket "DCC FAIL :File not found\n";
            }
        } elsif ($line =~ /^QUIT/) {
            print $client_socket "QUIT :Client disconnected\n";
            $select->remove($client_socket);
            close($client_socket);
            delete $clients{$client_socket};
            last;
        }
    }
}
