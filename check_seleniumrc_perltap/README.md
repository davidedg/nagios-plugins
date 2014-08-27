check_seleniumrc_perltap
========================

Nagios plugin for SELENIUM-1 (RC) Perl scripts

Instructions
------------

Install Selenium perl bindings and test libraries

	aptitude -y install libtest-www-selenium-perl
	aptitude -y install libtest-mock-lwp-perl

Install Selenium IDE (FIREFOX PLUGIN)

	http://www.seleniumhq.org/download/

Install Selenium IDE PERL Formatter

	https://addons.mozilla.org/en-US/firefox/addon/selenium-ide-perl-formatter/

Configure it:

	Options -> Options -> Formats
	Perl:

Insert into HEADER Section:

	use strict;
	use warnings;
	use Time::HiRes qw(sleep gettimeofday);
	use Test::WWW::Selenium;
	use Test::More "no_plan";
	use Test::Exception;

	my $timer0_i = gettimeofday;
	my ${receiver} = Test::WWW::Selenium->new( host => "${rcHost}", 
										port => ${rcPort}, 
										browser => "${environment}", 
										browser_url => "${baseURL}" );

	my $seleniumsession = $sel->{session_id};
	my $timer1_i = gettimeofday;

Insert into FOOTER Section:

	printf("PERF_TESTCASETOTAL:%.2f\n", gettimeofday-$timer1_i);
	printf("VAR_SESSIONID:%s\n",$seleniumsession);
	$sel->stop();
	printf("PERF_PLUGINTOTAL:%.2f\n", gettimeofday-$timer0_i);

Export test case as -> PERL


Now Run the exported script through my nagios plugin.

	check_seleniumrc_perltap.pl --script=testcase.pl

