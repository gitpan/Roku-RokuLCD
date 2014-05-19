#!perl -T
use 5.006;
use strict;
use warnings FATAL => 'all';
use Test::More;

plan tests => 1;

BEGIN {
    use_ok( 'Roku::RokuLCD' ) || print "Bail out!\n";
}

diag( "Testing Roku::RokuLCD $Roku::RokuLCD::VERSION, Perl $], $^X" );
