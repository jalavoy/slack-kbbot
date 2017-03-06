# KBbot
**THIS NO LONGER WORKS - ZKB NO LONGER SUPPORTS MY METHOD AND I DO NOT HAVE TIME TO REWORK IT. I SUGGEST USING THS FOLLOWING CODE INSTEAD. IT'S A NICER PACKAGE ANYWAY**

`https://github.com/dimurgos/Slack-Eve-Killmail`



Parses zkillboard to give an hour by hour feed of kills by a corporation or alliance.

Things you will need for this script:
- perl 5.8.8+
- slack
- Some linux/unix box, I haven't tested this with windows perl but it might work.
- some cron software
- The following perl modules:
```
FindBin
File::Touch
Getopt::Std
LWP::UserAgent
HTTP::Message
JSON::XS
XML::Simple
Data::Dumper
```

You'll want to automate this with cron (or whatever you want really) to run every hour. It looks like zkillboards API will just cache it harder if you hit it all the time, so no real reason to make it run any faster than that. You can do that by adding the following to your crontab:
```
0 * * * * /path/to/kbbot.pl
```

The configuration file is pretty self explanatory, you'll need to populate it with your corp or alliance's details.

You will need to make an Incoming Hook for the slack channel you want to post to. Go to Configure Integrations > Incoming WebHooks > Setup a hook and grab the Webhook URL. You should probably keep this information private too. As far as I can tell, anyone can post anything to a githook URL if they have the URL.

Be sure to run the script manually one time once your config file is setup. This will validate your configuration and initialize some stored variables.

This is to be considered alpha software. Please report any bugs you run into on github. If you are reporting a bug, please run the script with -d and send me the output.

Thanks!

Reve Uhad
Isogen 5
