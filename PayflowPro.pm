package Business::OnlinePayment::PayflowPro;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
use Carp qw(croak);
use AutoLoader;
use Business::OnlinePayment;

#PayflowPRO SDK from Verisign
use PFProAPI qw( pfpro );

require Exporter;

@ISA = qw(Exporter AutoLoader Business::OnlinePayment);
@EXPORT = qw();
@EXPORT_OK = qw();
$VERSION = '0.02';

sub set_defaults {
    my $self = shift;

    $self->server('payflow.verisign.com');
    $self->port('443');

    $self->build_subs(qw(
      vendor partner order_number cert_path avs_code cvv2_code
    ));

}

sub map_fields {
    my($self) = @_;

    my %content = $self->content();

    #ACTION MAP
    my %actions = ('normal authorization' => 'S', #Sale
                   'authorization only'   => 'A', #Authorization
                   'credit'               => 'C', #Credit (refund)
                   'post authorization'   => 'D', #Delayed Capture
                   'void'                 => 'V',
                  );
    $content{'action'} = $actions{lc($content{'action'})} || $content{'action'};

    # TYPE MAP
    my %types = ('visa'               => 'C',
                 'mastercard'         => 'C',
                 'american express'   => 'C',
                 'discover'           => 'C',
                 'cc'                 => 'C'
                 #'check'              => 'ECHECK',
                );
    $content{'type'} = $types{lc($content{'type'})} || $content{'type'};
    $self->transaction_type($content{'type'});

    # stuff it back into %content
    $self->content(%content);
}

sub build_subs {
    my $self = shift;
    foreach(@_) {
        #no warnings; #not 5.005
        local($^W)=0;
        eval "sub $_ { my \$self = shift; if(\@_) { \$self->{$_} = shift; } return \$self->{$_}; }";
    }
}

sub remap_fields {
    my($self,%map) = @_;

    my %content = $self->content();
    foreach(keys %map) {
        $content{$map{$_}} = $content{$_};
    }
    $self->content(%content);
}

sub revmap_fields {
    my($self, %map) = @_;
    my %content = $self->content();
    foreach(keys %map) {
#    warn "$_ = ". ( ref($map{$_})
#                         ? ${ $map{$_} }
#                         : $content{$map{$_}} ). "\n";
        $content{$_} = ref($map{$_})
                         ? ${ $map{$_} }
                         : $content{$map{$_}};
    }
    $self->content(%content);
}

sub get_fields {
    my($self,@fields) = @_;

    my %content = $self->content();
    my %new = ();
    foreach( grep defined $content{$_}, @fields) { $new{$_} = $content{$_}; }
    return %new;
}

sub submit {
    my($self) = @_;

    $self->map_fields();

    my %content = $self->content;

    my($month, $year, $zip);

    #unless ( $content{action} eq 'BillOrders' ) {

        if (  $self->transaction_type() eq 'C' ) {
        } else {
            Carp::croak("PayflowPro can't (yet?) handle transaction type: ".
                        $self->transaction_type());
        }

      if ( exists($content{'expiration'}) && defined($content{'expiration'})
           && length($content{'expiration'})                                 ) {
        $content{'expiration'} =~ /^(\d+)\D+\d*(\d{2})$/
          or croak "unparsable expiration $content{expiration}";

        ( $month, $year ) = ( $1, $2 );
        $month = '0'. $month if $month =~ /^\d$/;
      }

      ( $zip = $content{'zip'} ) =~ s/\D//g;
    #}

    #$content{'address'} =~ /^(\S+)\s/;
    #my $addrnum = $1;

    $self->server('test-payflow.verisign.com') if $self->test_transaction;

    $self->revmap_fields(
      ACCT       => 'card_number',
      EXPDATE     => \( $month.$year ),
      AMT         => 'amount',
      USER        => 'login',
      #VENDOR      => \( $self->vendor ),
      VENDOR      => 'login',
      PARTNER     => \( $self->partner ),
      PWD         => 'password',
      TRXTYPE     => 'action',
      TENDER      => 'type',

      STREET      => 'address',
      ZIP         => \$zip,

      CITY        => 'city',
      COMMENT1    => 'description',
      COMMENT2    => 'invoice_number',
      COMPANYNAME => 'company',
      COUNTRY     => 'country',
      FIRSTNAME   => 'first_name',
      LASTNAME    => 'last_name',
      NAME        => 'name',
      EMAIL       => 'email',
      STATE       => 'state',

      CVV2        => 'cvv2',
      ORIGID      => 'order_number'

    );

    my @required = qw( TRXTYPE TENDER PARTNER VENDOR USER PWD );
    if (  $self->transaction_type() eq 'C' ) { #credit card
      if ( $content{'action'} =~ /^[CDV]$/ && exists($content{'ORIGID'})
           && defined($content{'ORIGID'}) && length($content{'ORIGID'}) ) {
        push @required, qw(ORIGID);
      } else {
        push @required, qw(AMT ACCT EXPDATE);
      }
    }
    $self->required_fields(@required);

    my %params = $self->get_fields(qw(
      ACCT EXPDATE AMT USER VENDOR PARTNER PWD TRXTYPE TENDER
      STREET ZIP
      CITY COMMENT1 COMMENT2 COMPANYNAME COUNTRY FIRSTNAME LASTNAME NAME EMAIL
        STATE
      CVV2 ORIGID
    ));

    #print "$_ => $params{$_}\n" foreach keys %params;

    $ENV{'PFPRO_CERT_PATH'} = $self->cert_path;
    my( $response, $resultstr ) = pfpro( \%params, $self->server, $self->port );

    #if ( $response->{'RESULT'} == 0 ) {
    if ( $response->{'RESULT'} eq '0' ) { #want an explicit zero, not just
                                          #numerically equal
      $self->is_success(1);
      $self->result_code(   $response->{'RESULT'}   );
      $self->error_message( $response->{'RESPMSG'}  );
      $self->authorization( $response->{'AUTHCODE'} );
      $self->order_number(  $response->{'PNREF'}    );
      my $avs_code = '';
      if ( $response->{AVSADDR} eq 'Y' && $response->{AVSZIP} eq 'Y' ) {
        $avs_code = 'Y';
      } elsif ( $response->{AVSADDR} eq 'Y' ) {
        $avs_code = 'A';
      } elsif ( $response->{AVSZIP} eq 'Y' ) {
        $avs_code = 'Z';
      } elsif ( $response->{AVSADDR} eq 'N' || $response->{AVSZIP} eq 'N' ) {
        $avs_code = 'N';
      }
      $self->avs_code(      $avs_code               );
      $self->cvv2_code(     $response->{'CVV2MATCH'});
    } else {
      $self->is_success(0);
      $self->result_code(   $response->{'RESULT'}  );
      $self->error_message( $response->{'RESPMSG'} );
    }

}

1;
__END__

=head1 NAME

Business::OnlinePayment::PayflowPro - Verisign PayflowPro backend for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment;

  my $tx = new Business::OnlinePayment( 'PayflowPro',
    'vendor'    => 'your_vendor',
    'partner'   => 'your_partner',
    'cert_path' => '/path/to/your/certificate/file/', #just the dir
  );

  $tx->content(
      type           => 'VISA',
      action         => 'Normal Authorization',
      description    => 'Business::OnlinePayment test',
      amount         => '49.95',
      invoice_number => '100100',
      customer_id    => 'jsk',
      name           => 'Jason Kohles',
      address        => '123 Anystreet',
      city           => 'Anywhere',
      state          => 'UT',
      zip            => '84058',
      email          => 'ivan-payflowpro@420.am',
      card_number    => '4007000000027',
      expiration     => '09/04',

      #advanced params
      cvv2           => '420',
      order_number   => 'string', # returned by $tx->order_number() from an
                                  # "authorization only" or
                                  # "normal authorization" action, used by a
                                  # "credit", "void", or "post authorization"
  );
  $tx->submit();

  if($tx->is_success()) {
      print "Card processed successfully: ".$tx->authorization."\n";
      print "order number: ". $tx->order_number. "\n";
      print "AVS code: ". $tx->avs_code. "\n"; # Y - Address and ZIP match
                                               # A - Address matches but not ZIP
                                               # Z - ZIP matches bu tnot address
                                               # N - no match
                                               # E - AVS error or unsupported
                                               # (null) - AVS error
      print "CVV2 code: ". $tx->cvv2_code. "\n";

  } else {
      print "Card was rejected: ".$tx->error_message;
      print " (CVV2 mismatch)" if $tx->result_code == 114;
      print "\n";
  }

=head1 SUPPORTED TRANSACTION TYPES

=head2 Visa, MasterCard, American Express, JCB, Discover/Novus, Carte blanche/Diners Club, CC

=head1 SUPPORTED ACTIONS

=head2 Normal Authorization, Authorization Only, Post Authorization, Credit, Void

=head1 DESCRIPTION

For detailed information see L<Business::OnlinePayment>.

=head1 COMPATIBILITY

This module implements an interface to the PayflowPro Perl API, which can
be downloaded at https://manager.verisign.com/ with a valid login.

=head1 BUGS

=head1 AUTHOR

Ivan Kohler <ivan-payflowpro@420.am>

Based on Busienss::OnlinePayment::AuthorizeNet written by Jason Kohles.

=head1 SEE ALSO

perl(1), L<Business::OnlinePayment>.

=cut

