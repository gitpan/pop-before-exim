#!/usr/bin/perl -w
#
use strict;
use File::Tail;
use AppConfig;
use Sys::Syslog;
#my $version=0.5.1;

# File to watch for pop3d/imapd records
my $logfile = '/var/log/mail.log';
my $dbfile = '/var/lib/pop-before-smtp/hosts'; # DB hash to write
my $grace = 1800; # 30 minutes --- grace period

# For UW ipop3d/imapd, pattern tweaked by Stig Hackvan <stig@hackvan.com>
#my $pat = '^(... .. ..:..:..) \S+ (?:ipop3d|imapd)\[\d+\]: ' .
#          '(?:Login|Authenticated|Auth) user=(\S+) host=(\S+ )?\[(\d+\.\d+\.\d+\.\d+)\](?: nmsgs=\d+/\d+)?$';
#user natalia authenticated - localhost (127.0.0.1)
my $pat= '^(... .. ..:..:..) \S+ (?:solid-pop3d)\[\d+\]: ' .
'user (\S+) authenticated - (\S+) \((\d+\.\d+\.\d+\.\d+)\)';

# Login user=USER host=HOST [ip.ip.ip.ip] nmsgs=
# Initialize config
my $config = AppConfig->new();
$config->define("logfile=s", { DEFAULT => $logfile } );
$config->define("dbfile=s", { DEFAULT => $dbfile } );
$config->define("pat=s", { DEFAULT => $pat } );
$config->define("grace=i", { DEFAULT => $grace } );
$config->define("debug=i", { DEFAULT => 0 } );
$config->define("tick=i", { DEFAULT => 300 } );

# Read config from file
my $configfile = '/etc/pop-before-smtp/pop-before-smtp.conf';
$config->file($configfile);

#Open logfile to parse
my $fi = File::Tail->new(
    name => $config->logfile(),
    maxinterval => 2,
    interval => 1,
    adjustafter => 3,
    resetafter => 30,
    tail => -1,
);
my (%hosts);
#tie %hosts, 'DB_File', $ENV{HOME}.'/pbs-hosts.db' || die;

openlog ('pop-before-smtp', 'pid', 'mail');
sub say_goodbye {
  syslog('crit', "exiting on signal %s", $_[0]);
  closelog();
  exit(1);
}
$SIG{'INT'} = sub { say_goodbye('INT'); };
$SIG{'TERM'} = sub { say_goodbye('TERM'); };

$SIG{__DIE__} = sub { 
  syslog('crit', "fatal error %s (%m)", $_[0]);
  closelog();
  #untie %hosts;
  # perl will perform the exit...
};
syslog('info','starting pop-before-exim pbs...');

# Show running configuration
if ($config->debug()) {
    my ($configname, $configvalue);
    my %config = $config->varlist(".*");
    while (($configname, $configvalue) = each (%config)) {
	syslog('mail|warning', "Config: $configname: $configvalue");
    }
}
my $pattern = $config->pat();
$grace = $config->grace();
my $tick = $config->tick();

sub tick {
	my $time=time;
	#syslog('mail|info', "tick ticker at ".$time);
	foreach (keys(%hosts)) {
		if (($time-$hosts{$_})>$grace) {
			syslog('mail|warning', "Removin relay: ".$hosts{$_}.' for host '.$_);
			delete $hosts{$_};#usuwamy relaya
		} else { 
		syslog('mail|warning','Not removing relay: '.$hosts{$_}.' for host '.$_) if ($config->debug());
		}
	}
	my ($hosts);
	foreach (keys(%hosts)) {$hosts.=$_."\n";};
	open(H,">$dbfile");
	print H $hosts;
	close H;#TODO - locking...
alarm $tick;
}
$SIG{'ALRM'}=\&tick;
alarm 10;

#Main loop ;)
#
while (1) {
    $_ = $fi->read;
    m/$pattern/o or next;
    my ($timestamp,$user,$host,$ipaddr) = ($1,$2,$3,$4);
    if ($host) {
	    #syslog('mail|info', "read host=$host user=$user") if $config->debug();
	    {
		    do {
			    syslog('mail|info', "Opening relay for host=$host") if $config->debug();
			    open(H,">>$dbfile");
			    print H $host,"\n";
			    close H;#TODO - locking...
		    } unless (exists($hosts{$host})) ;
		    my $time=time;$hosts{$host}=$time;
	    }
    }
#syslog('info', "opening relay for $ipaddr --- not in mynetworks");
}


