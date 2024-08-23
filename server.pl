#!/usr/bin/perl
use strict;
use warnings;
use IO::Socket::INET;
use IO::Select;
use Net::DNS;
use IO::Socket::INET6;
use IO::Socket::SSL;
use File::Basename;
use Net::NAT::PMP;  # Uncomment if using NAT-PMP
use Net::UPnP::ControlPoint;  # Uncomment if using UPnP
# use Net::UPnP::IGD;  # Uncomment if using UPnP

# Server Configuration
my $server_port = 6667;  # Default port
my $server_name = 'localhostd';
my $internal_ip = '192.168.1.2';  # Replace with your internal IP
my %clients;
my %channels;
my %xdcc_packs;  # Store XDCC packs
my $select = IO::Select->new();

# Setup UPnP port mapping (commented out for now)
# sub setup_upnp {
#     my $cp = Net::UPnP::ControlPoint->new();
#     my @dev_list = $cp->search(st => 'upnp:rootdevice', mx => 3);
#     foreach my $d (@dev_list) {
#         if ($d->getdeviceType() =~ /InternetGatewayDevice/) {
#             my $igd = Net::UPnP::IGD->new();
#             $igd->setDevice($d);
#             return $igd;
#         }
#     }
#     return undef;
# }

# Map port using UPnP (commented out for now)
# sub map_port_upnp {
#     my ($igd, $internal_port, $external_port, $internal_ip) = @_;
#     return $igd->addPortMapping(
#         $external_port,
#         $internal_port,
#         $internal_ip,
#         'TCP',
#         'Test Mapping'
#     );
# }

# Map port using NAT-PMP
sub map_port_natpmp {
    my ($client, $internal_port, $external_port) = @_;
    return $client->add_port_mapping(
        protocol      => 'TCP',
        internal_port => $internal_port,
        external_port => $external_port,
        lifetime      => 3600,  # 1 hour
    );
}

# Determine SSL usage based on port
my $use_ssl = $server_port == 6697;

# Create a listening socket
my $server_socket;
eval {
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
            Domain        => AF_INET6,
            SSL_debug     => 1
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
};
if ($@) {
    die "Error creating socket: $@";
}

$select->add($server_socket);
print "IRC Server started on port $server_port\n";

# Try UPnP port mapping (commented out for now)
# my $igd = setup_upnp();
# if ($igd) {
#     if (map_port_upnp($igd, $server_port, $server_port, $internal_ip)) {
#         print "UPnP Port mapping successful: $server_port -> $server_port\n";
#     } else {
#         warn "Failed to map port via UPnP\n";
#     }
# } else {
#     print "No UPnP IGD device found.\n";
# }

# Attempt NAT-PMP mapping (commented out for now)
# my $client = Net::NAT::PMP->new();
# if (map_port_natpmp($client, $server_port, $server_port)) {
#     print "NAT-PMP Port mapping successful: $server_port -> $server_port\n";
# } else {
#     warn "Failed to map port via NAT-PMP: " . $client->error . "\n";
# }

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
            eval {
                handle_client($socket);
            };
            if ($@) {
                print "Error handling client: $@\n";
            }
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
            join_channel($client_socket, $client_info, $channel);
        } elsif ($line =~ /^PART\s+(#\S+)/) {
            my $channel = $1;
            part_channel($client_socket, $client_info, $channel);
        } elsif ($line =~ /^PING\s+(.*)/) {
            print $client_socket "PONG $1\n";
        } elsif ($line =~ /^QUIT/) {
            print $client_socket "QUIT :Client disconnected\n";
            $select->remove($client_socket);
            close($client_socket);
            delete $clients{$client_socket};
            last;
        } elsif ($line =~ /^PRIVMSG\s+(\S+)\s+:(.*)/) {
            my $target = $1;
            my $message = $2;
            foreach my $sock (keys %clients) {
                next if $sock == $client_socket;
                if (exists $channels{$target}->{$sock}) {
                    print $sock ":$client_info->{nick}!$client_info->{user}\@$client_info->{address} PRIVMSG $target :$message\n";
                }
            }
        } elsif ($line =~ /^TOPIC\s+(#\S+)\s+:(.*)/) {
            my $channel = $1;
            my $topic = $2;
            $channels{$channel}->{topic} = $topic;
            foreach my $sock (keys %{$channels{$channel}}) {
                print $sock ":$server_name TOPIC $channel :$topic\n";
            }
        } elsif ($line =~ /^WHOIS\s+(\S+)/) {
            my $nick = $1;
            foreach my $sock (keys %clients) {
                if ($clients{$sock}->{nick} eq $nick) {
                    print $client_socket ":$server_name 311 $clients{$sock}->{nick} $nick $clients{$sock}->{user} $clients{$sock}->{address} * :$clients{$sock}->{realname}\n";
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
            print $client_socket "PRIVMSG " . ($client_info->{nick} // 'unknown') . " :$response\n";
        } elsif ($line =~ /^DCC\s+SEND\s+(\S+)\s+(\S+)/) {
            my ($file_path, $file_size) = ($1, $2);
            if (-e $file_path) {
                open my $file, '<', $file_path or next;
                my $file_data = do { local $/; <$file> };
                close $file;
                print $client_socket "DCC SEND $file_path $file_size\n";
                print $client_socket $file_data;
            } else {
                print $client_socket "DCC FAIL :File not found\n";
            }
        } elsif ($line =~ /^XDCC\s+SEND\s+(\d+)/) {
            my $pack_number = $1;
            if (exists $xdcc_packs{$pack_number}) {
                my $file_path = $xdcc_packs{$pack_number}->{path};
                my $file_size = $xdcc_packs{$pack_number}->{size};
                open my $file, '<', $file_path or next;
                my $file_data = do { local $/; <$file> };
                close $file;
                print $client_socket "XDCC SEND $file_path $file_size\n";
                print $client_socket $file_data;
            } else {
                print $client_socket "XDCC FAIL :Pack not found\n";
            }
        } elsif ($line =~ /^XDCC\s+LIST/) {
            foreach my $pack_number (keys %xdcc_packs) {
                my $file_name = basename($xdcc_packs{$pack_number}->{path});
                print $client_socket "XDCC PACK $pack_number $file_name $xdcc_packs{$pack_number}->{size}\n";
            }
        } elsif ($line =~ /^TEST/) {
            # Respond with server status
            print $client_socket "TEST :Server is online\n";
        } else {
            print $client_socket "ERROR :Unknown command\n";
        }
    }
}

sub join_channel {
    my ($client_socket, $client_info, $channel) = @_;

    # Add the client to the channel's list
    $channels{$channel}->{$client_socket} = $client_info->{nick} // 'unknown';

    # Add the channel to the client's list of channels
    push @{$client_info->{channels}}, $channel;

    # Notify the client about the successful join
    print $client_socket ":$server_name 001 " . ($client_info->{nick} // 'unknown') . " :Welcome to the $channel channel\n";
    
    # Notify other clients in the channel about the new joiner
    foreach my $sock (keys %{$channels{$channel}}) {
        next if $sock == $client_socket;  # Skip the newly joined client
        print $sock ":$server_name JOIN $channel :" . ($client_info->{nick} // 'unknown') . " has joined $channel\n";
    }
}

sub part_channel {
    my ($client_socket, $client_info, $channel) = @_;

    # Remove the client from the channel's list
    delete $channels{$channel}->{$client_socket};

    # Remove the channel from the client's list of channels
    @{$client_info->{channels}} = grep { $_ ne $channel } @{$client_info->{channels}};

    # Notify the client about the successful part
    print $client_socket ":$server_name PART $channel :Leaving channel\n";

    # Notify other clients in the channel about the part
    foreach my $sock (keys %{$channels{$channel}}) {
        print $sock ":$server_name PART $channel :" . ($client_info->{nick} // 'unknown') . " has left $channel\n";
    }
}
