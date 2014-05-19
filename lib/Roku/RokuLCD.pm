package Roku::RokuLCD;

use v5.10.1;
use strict;
use warnings;
use Time::HiRes qw(sleep);

require Roku::RCP;

use parent qw(Roku::RCP);

our $VERSION = '0.03';

=head1 NAME

Roku::RokuLCD - M400 & M500 Display Functions made more accessible than via the Roku::RCP module

=head1 VERSION

=over

=item Version 0.03  March 24, 2014 Proper CPAN packaging and moved to using Roku::RCP as a base rather than the non-CPAN RokuUI module

=back

=head1 SYNOPSIS


 use Roku::RokuLCD;
 my $display = Roku::RokuLCD->new($rokuIP);
 if (! display) { die("Could not connect to Roku Soundbridge"); }
 
 my($rv) = $display->marquee(text => "This allows easy access to the marquee function - timings for M400 only");

 $display->ticker(text => "An alternative to the marquee function that can cope with large quantities of text", pause => 5);

 open (INFILE, "a_text_file.txt");
 @slurp_file = <INFILE>;
 close(INFILE);

 $display->teletype(text => "@slurp_file", pause => 2, linepause => 1);

 $display->Quit;

=head1 DESCRIPTION

Roku::RokuLCD was written because the RokuUI module appeared a bit too high level, so I put together some simplified display
routines into a single easy-to-use object.

It has now been moved to using the Roku::RCP module which is easily available from CPAN.

It inherits all the methods from the standard Roku::RCP module.

=head1 METHODS

=head2 new(host => I<host_address> [, port => I<port>] [, model => I<400 or 500>])

If not given, RokuLCD assumes that the port number is 4444, and will attempt to determine the model from the displaytype
command (if that fails, it will set the model type to M400).

=cut

sub new {
    my $self = shift;
    my $class = ref($self) || $self;
    my ( $host, %args );
    $host = shift if ( scalar(@_) % 2 );
    %args = @_;
    $args{Host} = $host if $host;

    if (! $args{Host}) { return; }

    $self = $class->SUPER::new( $host, Port => $args{Port} || '4444' );

    if (! defined $self)  { return; }

    if ( $args{model} ) {
	    if ( $args{model} == 500 ) {
	        ${*$self}{display_length} = 40;
            ${*$self}{model} = $args{model};
	    }
	    elsif ( $args{model} == 400 ) {
	        ${*$self}{display_length} = 16;
            ${*$self}{model} = $args{model};
	    }
	    else {
	    	print 'WARNING: unrecognised model type, ', ${*$self}{model}, " trying display type\n";
	    }
    }

    if (! ${*$self}{model} ) {
	    $self->command("displaytype");
	    # M400 returns "16x2 LCD" - I assume M500 returns "40x2 LCD"
	
	    my @responses = $self->sb_response();
	    foreach my $response (@responses) {
	
		    print "displaytype = '$response' ?\n";
		    if ($response =~ /^(\d{2})x/) {
		        ${*$self}{display_length} = $1;
		        if (${*$self}{display_length} == 40) {
		        	${*$self}{model} = 500;
		        }
		        else {
		            ${*$self}{model} = 400;
		        }
		        last;
		    }
	    }
	    
	    if (! ${*$self}{model}) {
            print "WARNING: unrecognised display type - unknown model type.  Setting to 16x2.\n";
	        ${*$self}{display_length} = 16;
	        ${*$self}{model} = 400;
	    }
	
	    if ( ${*$self}{debug} ) {
            print "DEBUG display length = ${*$self}{display_length}; model = ${*$self}{model} = 400\n";
	    }
    }

    return bless $self, $class;
}    # end new

=head2 marquee(text => I<text to display> [, clear => I<0/1>])

This allows quick access to the standard sketch marquee function - timings are for text sized to
the M400 display as I do not have access to an M500.

If 1 is passed to clear, it forces the display to clear first (default 0)

=cut

sub marquee {
    my ( $self, %args ) = @_;

    # only take over if on standby
    if (! $self->onstandby ) {
        return ("Soundbridge running");
    }
    my $text  = $args{'text'}  || '';
    my $clear = $args{'clear'} || 0;

    # duration is a magic number - time to wait before releasing display.
    my $duration = ( int( ( ( length($text) ) + 24 ) / 25 ) ) * 5;

    if ( ${*$self}{debug} ) {
        print "DEBUG text length = ", length($text),
          " duration = $duration\n";
    }

    if ($clear) { $self->_clear; }
    $self->command("sketch -c marquee -start \"$text\"");
    sleep($duration);
    $self->command('sketch -c quit');
    $self->command('sketch -c exit');

    return ($self->sb_response);
}    # end marquee


sub _clear {
	# clear the display
    my $self = shift;
    $self->command('sketch -c clear');
    my $rc = $self->sb_response;
    return ($rc);
}

sub _spacefill {
    # pad line with spaces - used to overwrite previous lines
    # WARNING! This is an internal function, and likely to change
    my ( $self, %args ) = @_;
    my $text = $args{'text'} || '';
    for ( my $i = length($text) ; $i <= ${*$self}{display_length} ; $i++ ) {
        $text .= ' ';
    }
    return $text;
}    # end _spacefill

sub _text {

# internal function allowing easy access to the sketch "text" command
# usage:
#   _text(text => I<text to display> , duration => I<length of time to display> [, clear => I<0/1>], x => I<c/0-screen width>, y => I<0/1>)
    my ( $self, %args ) = @_;

    my $text  = $args{'text'}  || '';
    my $x     = $args{'x'}     || 0;
    my $y     = $args{'y'}     || 0;
    my $duration = $args{'duration'};

    $self->command("text $x $y \"$text\"");
    sleep($duration);
    return 1;
}    # end _text

=head2 ticker(text => I<text to display> [, y => I<0/1>] [, pause => I<seconds>])

An alternative to the marquee that can be displayed on either the top or bottom line.

=cut

sub ticker {    # an alternative to marquee
    my ( $self, %args ) = @_;
    # only take over if on standby
    if (! $self->onstandby ) {
        return ('Soundbridge running');
    }
    
    $self->command('sketch');

    $self->_ticker(%args);

    $self->command('quit');
    my $rc = $self->sb_response;
    return ($rc);
} # end ticker


sub _ticker {    # the real function - also used by teletype
    my ( $self, %args ) = @_;
    my $text  = $args{'text'}  || '';
    my $pause = $args{'pause'} || 5;
    my $y     = $args{'y'}     || 0;
    my $dlength = ${*$self}{display_length};
    my $offset  = 0;
    my $tlength = 0;
    my $dtext   = 0;
    my $dur     = 0;
    my $spc     = 0;

    my $length = 0;
    while(++$length < ( length($text) ) ) {
        $spc++;
        $tlength++ unless ( $tlength == $dlength );
        $offset++ if ( length($dtext) == $dlength );
        $dtext = substr( $text, $offset, $tlength );
        $spc = 0 if ( substr( $dtext, -1, 1 ) eq ' ' );

        if ( ( length($text) > $dlength ) && ( ++$dur == $dlength ) ) {
            # print "length > dlength && dur == dlength\n";
            $self->_text( text => $dtext, duration => 0.25, y => $y );
            if ( ${*$self}{debug} ) {
                print "DEBUG dtext='$dtext' dur='$dur' spc='$spc'\n";
            }
            $dur = $spc;
            $dur = 0 if ( $dur > $dlength );
        }
        else {
            # print "length <= dlength || dur != dlength\n";
            $self->_text( text => $dtext, duration => 0.25, y => $y );
            if ( ${*$self}{debug} ) {
                print "DEBUG dtext='$dtext' dur='$dur' spc='$spc'\n";
            }
        }
    }
    $dtext = substr( $text, -$dlength, $dlength );
    $self->_text( text => $dtext, duration => $pause, y => $y );
    return 1;
}    # end _ticker

=head2 teletype(text => I<text to display> [, pause => I<seconds>] [, [linepause =>  I<seconds>])

An alternative to using marquee to display large quantities of text, scrolling the display upwards rather than from 
the right.

The length of time to pause after each line of text is given by I<linepause>, wheras I<pause> holds the
length of time to pause at the end of the text.

=cut

sub teletype {
    my ( $self, %args ) = @_;
    my $text      = $args{'text'}      || ''; # default text is blank
    my $linepause = $args{'linepause'} || 1;  # length of time to wait in seconds before next line
    my $pause     = $args{'pause'}     || 1;  # length of additional time to wait in seconds after message

    # only take over if on standby
    if (! $self->onstandby ) {
    	return ("Soundbridge running");
    }

    $self->command('sketch'); # put the command session into sketch mode

    # Clear display first
    $self->_clear;

    my @string;
    my $rc;                                      # message returned by method
    my $dlength     = ${*$self}{display_length}; # width of display
    my $line_length = 0;                         # current length of line
    my $y           = 0;                         # start at the top
    my $y0_string   = undef;                     # used to build the top string
    my $y1_string   = undef;                     # used to build the bottom string

    my (@paras) = split( /\n/, $text );  # break the text into paragraphs
    foreach (@paras) {
        @string = split(/ /);            # break the paragraph into words (split on space)

        # work through each word in the array (ary_inx holds the current word's position)
        for ( my $ary_inx = 0 ; $ary_inx <= $#string ; $ary_inx++ ) {

            if ( ( length( $string[$ary_inx] ) + $line_length ) <
                $dlength )
                # if the word will fit on the current line
                # (note less than as a space needs to be accomodated too)
            {
                if ( $y == 0 ) {
                    $y0_string .= ' ' if ($y0_string);
                    $y0_string .= $string[$ary_inx];
                    $line_length += ( length( $string[$ary_inx] ) );
                    $line_length++;
                }
                else    # we'll assume it's line 1
                {
                    $y1_string .= ' ' if ($y1_string);
                    $y1_string .= $string[$ary_inx];
                    $line_length += ( length( $string[$ary_inx] ) );
                    $line_length++;
                }
            }
            # elsif the word will not fit on the current line but contains a non-word character - split on that (add one to the length because there's a space)
            elsif ( ( $string[$ary_inx] =~ /^(\S+\W)(\S+)$/ )
                && ( ( length($1) + $line_length + 1 ) <
                    $dlength ) )
            {
                if ( $y == 0 ) {
                    $y0_string .= ' ' if ($y0_string);
                    $y0_string .= $1;
                    $rc = $self->_ticker(
                        text    => $y0_string,
                        y       => 0,
                        pause   => 0.25
                    );
                    $y           = 1;
                    $y1_string   = $2;
                    $line_length = length($2);
                }
                else {
                    $y1_string .= ' ' if ($y1_string);
                    $y1_string .= $1;
                    $rc = $self->_text(
                        text     => $y0_string,
                        duration => 0,
                        y        => 0
                    );
                    $rc = $self->_text(
                        text     => $self->_spacefill( text => ' ' ),
                        duration => 0,
                        y        => 1
                    );
                    $rc = $self->_ticker(
                        text    => $y1_string,
                        y       => 1,
                        pause   => 0.25
                    );
                    $y0_string = substr(
                        $y1_string,
                        ( -$dlength ),
                        $dlength
                    );    # only display what was on 2nd line
                    $y1_string   = $2;
                    $line_length = length($2);
                }
            }
            else {        # too big for line
                if ( $y == 0 ) {
                    $rc = $self->_ticker(
                        text    => $y0_string,
                        y       => 0,
                        pause   => 0.25
                    );
                    $y           = 1;
                    $y1_string   = $string[$ary_inx];
                    $line_length = ( length( $string[$ary_inx] ) );
                }
                else {
                    $rc = $self->_text(
                        text     => $self->_spacefill( text => $y0_string ),
                        duration => 0,
                        y        => 0
                    );
                    $rc = $self->_text(
                        text     => $self->_spacefill( text => ' ' ),
                        duration => 0,
                        y        => 1
                    );
                    $rc = $self->_ticker(
                        text    => $y1_string,
                        y       => 1,
                        pause   => 0.25
                    );
                    $y0_string = substr(
                        $y1_string,
                        ( -$dlength ),
                        $dlength
                    );    # only display what was on 2nd line
                    $y1_string   = $string[$ary_inx];
                    $line_length = ( length( $string[$ary_inx] ) );
                }
            }
        }
        unless ( $rc =~ /^CK/ ) {
            if ($y1_string) {
                $rc = $self->_text(
                    text     => $self->_spacefill( text => $y0_string ),
                    duration => 0,
                    y        => 0
                );
                $rc = $self->_text(
                    text     => $self->_spacefill( text => ' ' ),
                    duration => 0,
                    y        => 1
                );
                $rc = $self->_ticker(
                    text     => $y1_string,
                    pause    => $linepause,
                    y        => 1
                );
            }
            else {
                for ( my $i = length($y0_string) ; $i <= 16 ; $i++ ) {
                    $y0_string .= ' ';
                }
                $rc = $self->_text(
                    text     => $y0_string,
                    duration => 0,
                    y        => 0
                );
                $rc = $self->_text(
                    text     => $self->_spacefill( text => ' ' ),
                    duration => $linepause,
                    y        => 1
                );
            }
        }
        $y         = 1;
        $y0_string = substr(
            $y1_string,
            ( -$dlength ),
            $dlength
        );    # only display what was on 2nd line
        $y1_string   = undef;
        $line_length = 0;
    }
    unless ( $rc =~ /^CK/ ) {
        if ($y1_string) {
            $rc = $self->_text(
                text     => $y0_string,
                duration => 0,
                y        => 0
            );
            $rc = $self->_text(
                text     => $self->_spacefill( text => ' ' ),
                duration => 0,
                y        => 1
            );
            $rc = $self->_text(
                text     => $y1_string,
                duration => $linepause,
                y        => 1
            );
        }
        else {
            $rc = $self->_text(
                text     => $self->_spacefill( text => $y0_string ),
                duration => 0,
                y        => 0
            );
            $rc = $self->_text(
                text     => $self->_spacefill( text => ' ' ),
                duration => $linepause,
                y        => 1
            );
        }
    }
    sleep($pause);
    $self->command('quit');
    $rc = $self->sb_response;
    return ($rc);
}    # end teletype

=head2 onstandby

Checks whether the Soundbridge is on standby (returns true) or in use (returns false)

=cut

sub onstandby {

    # an almost direct lift of RokuUI's ison function
    # this is used to see whether the radio is in use
    my $self = shift;
    $self->command("ps");

    for my $ps ( $self->sb_response ) {
        return 1 if $ps =~ /StandbyApp/;
    }
    return 0;
}    # end onstandby

=head2 sb_response

Used to return any command responses; filtering out prompts

=cut

sub sb_response {

    # this is used to return any command responses, but filter out prompts
    my $self = shift;
    return map {
        if ( ( !/^SoundBridge\>/ ) && ( !/^Sketch>/ ) ) { $_; }
    } $self->response();
}    # end sb_response

1;

# end of module, additional documentation below

__END__

=head1 STANDARD VARIABLES

=head2 clear

=over 4

=item * 0 (default) do not clear display first

=item * 1 clear display first

=back


=head1 BUGS AND LIMITATIONS

=head2 To do list

=over 4

=item * teletype method requires refactoring.

=back

=head1 AUTHOR

Outhwaite, Ed, C<< <edster at gmx.com> >>


=head1 ACKNOWLEDGEMENTS

Both ticker and teletype were inspired by Rod Lord's work on the Hitch-Hiker's Guide to the Galaxy TV program.
http://www.rodlord.com/pages/hhgg.htm


=head1 LICENSE AND COPYRIGHT

Copyright 2014 Outhwaite, Ed.

This program is free software; you can redistribute it and/or modify it
under the terms of the the Artistic License (2.0). You may obtain a
copy of the full license at:

L<http://www.perlfoundation.org/artistic_license_2_0>

Any use, modification, and distribution of the Standard or Modified
Versions is governed by this Artistic License. By using, modifying or
distributing the Package, you accept this license. Do not use, modify,
or distribute the Package, if you do not accept this license.

If your Modified Version has been derived from a Modified Version made
by someone other than you, you are nevertheless required to ensure that
your Modified Version complies with the requirements of this license.

This license does not grant you the right to use any trademark, service
mark, tradename, or logo of the Copyright Holder.

This license includes the non-exclusive, worldwide, free-of-charge
patent license to make, have made, use, offer to sell, sell, import and
otherwise transfer the Package with respect to any patent claims
licensable by the Copyright Holder that are necessarily infringed by the
Package. If you institute patent litigation (including a cross-claim or
counterclaim) against any party alleging that the Package constitutes
direct or contributory patent infringement, then this Artistic License
to you shall terminate on the date that such litigation is filed.

Disclaimer of Warranty: THE PACKAGE IS PROVIDED BY THE COPYRIGHT HOLDER
AND CONTRIBUTORS "AS IS' AND WITHOUT ANY EXPRESS OR IMPLIED WARRANTIES.
THE IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR
PURPOSE, OR NON-INFRINGEMENT ARE DISCLAIMED TO THE EXTENT PERMITTED BY
YOUR LOCAL LAW. UNLESS REQUIRED BY LAW, NO COPYRIGHT HOLDER OR
CONTRIBUTOR WILL BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, OR
CONSEQUENTIAL DAMAGES ARISING IN ANY WAY OUT OF THE USE OF THE PACKAGE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

RokuUI is Copyright Michael Polymenakos 2007 mpoly@panix.com


=cut

