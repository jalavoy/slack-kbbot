#!/usr/bin/perl
# this is a script that will pull killboard data from zkillboards API and feed it into a slack channel.
# Setup a cronjob to run this once an hour on the host machine. You're most likely going to hit caching limitations on zkb's API anyway, so no real reason to make it run more often than that. Something like this:
# 0 * * * * /path/to/script/kbbot.pl
# this script does NOT need to run as root
use strict;
use FindBin;
use File::Touch;
use Getopt::Std qw(getopts);
use LWP::UserAgent;
use HTTP::Message;
use JSON::XS;
use XML::Simple;
use Data::Dumper;

my $last_file = $FindBin::RealBin . '/.lastkill';
my $conf_file = $FindBin::RealBin . '/.kbbot.conf';
my $user_agent = 'Slack KBbot v1.0 - https://github.com/jalavoy/slack-kbbot';
my $ua = LWP::UserAgent->new();
$ua->timeout(10);
$ua->agent($user_agent);

my %opt = ();
getopts('vdh', \%opt);

if ( $opt{'h'} ) {
	print "[!] Usage: $0 [-v] [-d]\n";
	exit();
}

my $conf = get_config();

main();

sub main {
	my $last_seen = get_last();
	my $data = get_kills($last_seen);
	my ( $message, $ids ) = generate($data, $last_seen);
	tell_slack($message);
	cleanup($ids);
}

sub get_last {
	my $last_seen;
	if ( ! -f $last_file ) {
		touch($last_file);
	} else {
		open(my $DAT, '<', $last_file);
			chomp($last_seen = <$DAT>);
		close($DAT);
	}
	if ( $last_seen =~ /^[0-9]+$/ ) {
		print "Pulled [$last_seen] for last seen kill id.\n" if $opt{'v'};
		return($last_seen);
	} else {
		return(0);
	}
}

sub get_kills {
	my $last_seen = shift;
	my $uri;
	if ( $last_seen ) {
		$uri = 'http://zkillboard.com/api/kills/' . $conf->{'kb_type'} . 'ID/' . $conf->{'target_id'} . '/afterKillID/' . $last_seen . '/';
	} else {
		$uri = 'http://zkillboard.com/api/kills/' . $conf->{'kb_type'} . 'ID/' . $conf->{'target_id'} . '/';
	}
	my $response = $ua->get($uri, 'Accept-Encoding' => HTTP::Message::decodable);
	$response = $response->decoded_content( charset => 'none', raise_error => 0 );
	$response = decode_json($response);
	print Dumper $response if $opt{'d'};
	if ( $#{$response} <= 0 ) {
		print "No new kills found.\n" if $opt{'v'};
		exit();
	} else {
		return($response);
	}
}

sub generate {
	my $data = shift;
	my $last_seen = shift;
	my $text;
	print "Parsing data.\n" if $opt{'v'};
	if ( $last_seen ) {
		$text .= "The following kill(s) have been recorded in the last hour:\n";
	} else { 
		$text .= "Hi there! I am working properly. If you haven't already, setup your cron job now. I will pull new data after this point. \n";
	}
	my @ids;
	foreach my $kill ( reverse(@{$data}) ) {
		if ( $last_seen ) {
			print Dumper $kill if $opt{'d'};
			$text .= 'https://zkillboard.com/kill/' . $kill->{'killID'} . "\n";
			$text .= 'Time: ' . $kill->{'killTime'} . "\n";
			$text .= 'Victim: ' . $kill->{'victim'}->{'characterName'} . ' - ' . $kill->{'victim'}->{'corporationName'} . ' - ' . $kill->{'victim'}->{'allianceName'} . "\n";
			$text .= 'Ship: ' . get_ship($kill->{'victim'}->{'shipTypeID'}) . "\n";
			foreach my $attacker ( @{$kill->{'attackers'}} ) {
				if ( $attacker->{'finalBlow'} ) {
					$text .= 'Killing Blow: ' . $attacker->{'characterName'} . ' - ' . $attacker->{'corporationName'} . ' - ' . $kill->{'victim'}->{'allianceName'} . "\n";
					last;
				}
			}
			$text .= 'Value: ' . commify($kill->{'zkb'}->{'totalValue'}) . " ISK\n";
			$text .= "\n\n";
		}
		push(@ids, $kill->{'killID'});
	}
	if ( $#ids <= 0 ) {
		print "No kills to report.\n" if $opt{'v'};
		exit();
	} else {
		return($text, \@ids);
	}
}

sub tell_slack {
	my $text = shift;

	print "Sending data to Slack\n" if $opt{'v'};
	my $payload = {
		channel => $conf->{'channel'},
		username => $conf->{'username'},
		icon_emoji => $conf->{'emoji'},
		text => $text
	};

	my $json = encode_json($payload);
	my $req = HTTP::Request->new( 'POST', $conf->{'slack_hook_url'} );
	$req->header( 'Content-Type' => 'application/json' );
	$req->content($json);
	my $response = $ua->request($req);
	print Dumper $response if $opt{'d'};
}

sub cleanup {
	my $ids = shift;
	my @sorted = sort { $b <=> $a } @{$ids};
	my $last = shift(@sorted);
	open(my $WAT, '>', $last_file);
		print $WAT $last;
	close($WAT);
	return();
}

sub get_ship {
	my $id = shift;
	my $ua = LWP::UserAgent->new();
        $ua->timeout(10);
        $ua->agent($user_agent);
        my $response = $ua->get('https://api.eveonline.com/eve/TypeName.xml.aspx?ids=' . $id);
	print Dumper $response if $opt{'d'};
	my $ship = $response->content();
        my $ship = XMLin($response->content());
        return($ship->{'result'}->{'rowset'}->{'row'}->{'typeName'});
}

sub get_config {
	my %conf;
	open(my $DAT, '<', $conf_file);
		while(<$DAT>) {
			next if ( /^#/ );
			if ( /^(.*)=(.*)$/ ) {
				$conf{$1} = $2;
			}
		}
	close($DAT);
	my %validations = (
		target_id => '^[0-9]+$',
		kb_type => '^(corporation|alliance)$',
		slack_hook_url => '^http:\/\/hooks\.slack\.com\/services\/[0-0a-zA-Z]+\/[0-0a-zA-Z]+\/[0-0a-zA-Z]+$',
		channel => '^(#)?[a-zA-Z0-9]+$',
		username => '^[a-zA-Z0-9\-\_]+$',
		emoji => '^:[a-zA-Z0-9\-\_]+:$',
	);
	foreach my ( $key, $value ) ( each %validations ) {
		if ( $conf{$key} !~ /$value/ ) {
			die "$key does not have valid input: $key, $conf{$key}, $value\n";
		}
	}
	return(\%conf);
}

sub commify {
	my $input = shift;
	($input) = split(/\./, $input);
	$input = reverse($input);
	$input =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return reverse($input);
}


