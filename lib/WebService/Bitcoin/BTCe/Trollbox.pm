package WebService::Bitcoin::BTCe::Trollbox;
# ABSTRACT: provides access to btc-e.com messages
use strict;
use warnings;

use parent qw(IO::Async::Notifier);

our $VERSION = '0.001';

=head1 NAME

WebService::Bitcoin::BTCe::Trollbox - realtime messages from the btc-e.com feed

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

use Mixin::Event::Dispatch::Bus;
use Net::Async::WebSocket::Client;
use IO::Async::SSL;
use HTML::Entities ();
use JSON::MaybeXS;
use curry::weak;
use Log::Any qw($log);

=head1 METHODS

=cut

sub bus { shift->{bus} //= Mixin::Event::Dispatch::Bus->new }

sub json { shift->{json} //= JSON::MaybeXS->new( allow_nonref => 1) }

sub incoming_frame {
	my $self = shift;
	my ($client, $frame) = @_;

	eval {
		my $info = $json->decode($frame);
		if($info->{event} eq 'msg') {
			my $data = $json->decode($json->decode($info->{data}));
			$self->bus->invoke_event(
				message =>
					login => $data->{login},
					text =>  HTML::Entities::decode_entities($data->{msg}),
					time =>  time,
			);
		}
		1
	} or do {
		my $err = $@;
		$log->errorf("Unexpected frame (%s) [%s]", $err, $frame);
		$self->bus->invoke_event(
			error => $err, $frame
		);
	}
}

sub incoming_message {
	my $self = shift;
	my %args = @_;
	$self->fire_event(message_received => \%args);

	{
		my $histqueue = $self->get_prop_history;
		my $overcount = @$histqueue + 1 - 50;
		$self->shift_prop_history($overcount) if $overcount > 0;
	}
	$self->push_prop_history(\%args);
	return \%args;
}

sub _add_to_loop {
	my $self = shift;

	# Loop holds this for us...
	$self->add_child(
		my $client = Net::Async::WebSocket::Client->new(
			on_frame => $self->curry::weak::incoming_frame,
		)
	);

	$client->connect(
		host    => 'ws.pusherapp.com',
		service => 443,
		url     => "wss://ws.pusherapp.com/app/4e0ebd7a8b66fa3554a4?protocol=6&client=js&version=2.0.0&flash=false",
		extensions => [ qw(SSL) ],

		on_connected => sub {
			warn "connected: @_";
			my $client = shift;
			$client->send_frame('{"event":"pusher:subscribe","data":{"channel":"chat_en"}}');
		},

		on_connect_error => sub { die "Cannot connect - $_[-1]" },
		on_resolve_error => sub { die "Cannot resolve - $_[-1]" },
		on_ssl_error => sub { die "Cannot SSL - $_[-1]" },
	);
}

1;

__END__

=head1 SEE ALSO

=head1 AUTHOR

Tom Molesworth <cpan@perlsite.co.uk>

=head1 LICENSE

Copyright Tom Molesworth 2015. Licensed under the same terms as Perl itself.

