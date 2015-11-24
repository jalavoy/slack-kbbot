#!/usr/local/bin/perl
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
use Data::Dumper;

### START EDITS HERE
my $kb_type = 'corporation'; # valid options = corporation or alliance
my $target_id = 824518128; # you can get this from visiting your corp or alliances kill feed on zkillboard. It'll be the number in the URL, This is Goons for example: https://zkillboard.com/alliance/824518128/
my $slack_hook_url = 'https://hooks.slack.com/services/some/slack/hook/url'; # slack hook url, you would get this from creating a new incoming webhook in slack. Go to Configure Integrations > Incoming WebHooks > Setup a hook and grab the Webhook URL
my $channel = '#kb'; # the channel name you'd like to post to
my $username = 'KBbot'; # the username you'd like the bot to use
my $emoji = ':glitch_crab:'; # the emoji you want to use for your bots "buddy icon" in slack.
### STOP EDITS HERE

my $last_file = $FindBin::RealBin . '/.lastkill';
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

main();

sub main {
	my $last_seen = get_last();
	my $data = get_kills($last_seen);
	my ( $message, $ids ) = generate($data);
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
		$uri = 'http://zkillboard.com/api/kills/' . $kb_type . 'ID/' . $target_id . '/afterKillID/' . $last_seen . '/';
	} else {
		$uri = 'http://zkillboard.com/api/kills/' . $kb_type . 'ID/' . $target_id . '/';
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
	print "Parsing data.\n" if $opt{'v'};
	my $text = "The following kill(s) have been recorded in the last hour:\n";
	my @ids;
	foreach my $kill ( reverse(@{$data}) ) {
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
		channel => $channel,
		username => $username,
		icon_emoji => $emoji,
		text => $text
	};

	my $json = encode_json($payload);
	my $req = HTTP::Request->new( 'POST', $slack_hook_url );
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
        my $response = $ua->get('http://v3trae.net/eve/item_lookup.php?id=' . $id);
	return($response->content());
}

sub commify {
	my $input = shift;
	($input) = split(/\./, $input);
	$input = reverse($input);
	$input =~ s/(\d\d\d)(?=\d)(?!\d*\.)/$1,/g;
	return reverse($input);
}


