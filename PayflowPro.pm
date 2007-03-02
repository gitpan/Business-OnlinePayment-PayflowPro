package Business::OnlinePayment::PayflowPro;

use strict;
use vars qw($VERSION);
use Carp qw(croak);
use base qw(Business::OnlinePayment);

# Payflow Pro SDK
use PFProAPI qw( pfpro );

$VERSION = '0.06';
$VERSION = eval $VERSION;

sub set_defaults {
    my $self = shift;

    $self->server('payflow.verisign.com');
    $self->port('443');

    $self->build_subs(
        qw(
          vendor partner cert_path order_number avs_code cvv2_code
          )
    );
}

sub map_fields {
    my ($self) = @_;

    my %content = $self->content();

    #ACTION MAP
    my %actions = (
        'normal authorization' => 'S',    # Sale transaction
        'credit'               => 'C',    # Credit (refund)
        'authorization only'   => 'A',    # Authorization
        'post authorization'   => 'D',    # Delayed Capture
        'void'                 => 'V',    # Void
    );

    $content{'action'} = $actions{ lc( $content{'action'} ) }
      || $content{'action'};

    # TYPE MAP
    my %types = (
        'visa'             => 'C',
        'mastercard'       => 'C',
        'american express' => 'C',
        'discover'         => 'C',
        'cc'               => 'C',
        #'check'            => 'ECHECK',
    );

    $content{'type'} = $types{ lc( $content{'type'} ) } || $content{'type'};

    $self->transaction_type( $content{'type'} );

    # stuff it back into %content
    $self->content(%content);
}

sub remap_fields {
    my ( $self, %map ) = @_;

    my %content = $self->content();
    foreach ( keys %map ) {
        $content{ $map{$_} } = $content{$_};
    }
    $self->content(%content);
}

sub revmap_fields {
    my ( $self, %map ) = @_;
    my %content = $self->content();
    foreach ( keys %map ) {
        $content{$_} =
          ref( $map{$_} )
          ? ${ $map{$_} }
          : $content{ $map{$_} };
    }
    $self->content(%content);
}

sub submit {
    my ($self) = @_;

    $self->map_fields();

    my %content = $self->content;

    my ( $month, $year, $zip );

    if ( $self->transaction_type() ne 'C' ) {
        croak( "PayflowPro can't (yet?) handle transaction type: "
              . $self->transaction_type() );
    }

    if ( defined( $content{'expiration'} ) && length( $content{'expiration'} ) )
    {
        $content{'expiration'} =~ /^(\d+)\D+\d*(\d{2})$/
          or croak "unparsable expiration $content{expiration}";

        ( $month, $year ) = ( $1, $2 );
        $month = '0' . $month if $month =~ /^\d$/;
    }

    ( $zip = $content{'zip'} ) =~ s/[^[:alnum:]]//g;

    $self->server('test-payflow.verisign.com') if $self->test_transaction;

    $self->revmap_fields(

        # (BUG?) VENDOR B::OP:PayflowPro < 0.05 backward compatibility.  If
        # vendor not set use login (although test indicate undef vendor is ok)
        VENDOR      => $self->vendor ? \( $self->vendor ) : 'login',
        PARTNER     => \( $self->partner ),
        USER        => 'login',
        PWD         => 'password',
        TRXTYPE     => 'action',
        TENDER      => 'type',
        ORIGID      => 'order_number',
        COMMENT1    => 'description',
        COMMENT2    => 'invoice_number',

        ACCT        => 'card_number',
        CVV2        => 'cvv2',
        EXPDATE     => \( $month . $year ), # MM/YY from 'expiration'
        AMT         => 'amount',

        FIRSTNAME   => 'first_name',
        LASTNAME    => 'last_name',
        NAME        => 'name',
        EMAIL       => 'email',
        COMPANYNAME => 'company',
        STREET      => 'address',
        CITY        => 'city',
        STATE       => 'state',
        ZIP         => \$zip,               # 'zip' with non-alnums removed
        COUNTRY     => 'country',
    );

    my @required = qw( TRXTYPE TENDER PARTNER VENDOR USER PWD );
    if ( $self->transaction_type() eq 'C' ) {    # credit card
        if (   $content{'action'} =~ /^[CDV]$/
            && defined( $content{'ORIGID'} )
            && length( $content{'ORIGID'} ) )
        {
            push @required, qw(ORIGID);
        }
        else {
            # never get here, we croak above if transaction_type ne 'C'
            push @required, qw(AMT ACCT EXPDATE);
        }
    }
    $self->required_fields(@required);

    my %params = $self->get_fields(
        qw(
          VENDOR PARTNER USER PWD TRXTYPE TENDER ORIGID COMMENT1 COMMENT2
          ACCT CVV2 EXPDATE AMT
          FIRSTNAME LASTNAME NAME EMAIL COMPANYNAME
          STREET CITY STATE ZIP COUNTRY
          )
    );

    $ENV{'PFPRO_CERT_PATH'} = $self->cert_path;
    my ( $response, $resultstr ) =
      pfpro( \%params, $self->server, $self->port );

    # AVS and CVS values may be set on success or failure
    my $avs_code;
    if ( exists $response->{AVSADDR} || exists $response->{AVSZIP} ) {
        if ( $response->{AVSADDR} eq 'Y' && $response->{AVSZIP} eq 'Y' ) {
            $avs_code = 'Y';
        }
        elsif ( $response->{AVSADDR} eq 'Y' ) {
            $avs_code = 'A';
        }
        elsif ( $response->{AVSZIP} eq 'Y' ) {
            $avs_code = 'Z';
        }
        elsif ( $response->{AVSADDR} eq 'N' || $response->{AVSZIP} eq 'N' ) {
            $avs_code = 'N';
        }
        else {
            $avs_code = '';
        }
    }

    $self->avs_code($avs_code);
    $self->cvv2_code( $response->{'CVV2MATCH'} );
    $self->result_code( $response->{'RESULT'} );
    $self->order_number( $response->{'PNREF'} );
    $self->error_message( $response->{'RESPMSG'} );
    $self->authorization( $response->{'AUTHCODE'} );

    # RESULT must be an explicit zero, not just numerically equal
    if ( $response->{'RESULT'} eq '0' ) {
        $self->is_success(1);
    }
    else {
        $self->is_success(0);
    }
}

1;

__END__

=head1 NAME

Business::OnlinePayment::PayflowPro - Payflow Pro backend for Business::OnlinePayment

=head1 SYNOPSIS

  use Business::OnlinePayment;
  
  my $tx = new Business::OnlinePayment(
      'PayflowPro',
      'vendor'    => 'your_vendor',
      'partner'   => 'your_partner',
      'cert_path' => '/path/to/your/certificate/file/',    # just the dir
  );
  
  # See the module documentation for details of content()
  $tx->content(
      type           => 'VISA',
      action         => 'Normal Authorization',
      description    => 'Business::OnlinePayment::PayflowPro test',
      amount         => '49.95',
      invoice_number => '100100',
      customer_id    => 'jsk',
      name           => 'Jason Kohles',
      address        => '123 Anystreet',
      city           => 'Anywhere',
      state          => 'GA',
      zip            => '30004',
      email          => 'ivan-payflowpro@420.am',
      card_number    => '4111111111111111',
      expiration     => '12/09',
      cvv2           => '123',
      order_number   => 'string',
  );
  
  $tx->submit();
  
  if ( $tx->is_success() ) {
      print(
          "Card processed successfully: ", $tx->authorization, "\n",
          "order number: ",                $tx->order_number,  "\n",
          "CVV2 code: ",                   $tx->cvv2_code,     "\n",
          "AVS code: ",                    $tx->avs_code,      "\n",
      );
  }
  else {
      my $info = "";
      $info = " (CVV2 mismatch)" if ( $tx->result_code == 114 );
      
      print(
          "Card was rejected: ", $tx->error_message, $info, "\n",
          "order number: ",      $tx->order_number,         "\n",
      );
  }

=head1 DESCRIPTION

This module is a back end driver that implements the interface
specified by L<Business::OnlinePayment> to support payment handling
via the PayPal's Payflow Pro Internet payment solution.

See L<Business::OnlinePayment> for details on the interface this
modules supports.

=head1 Module specific methods

This module provides the following methods which are not currently
part of the standard Business::OnlinePayment interface:

=over 4

=item vendor()

=item partner()

=item cert_path()

=item L<order_number()|/order_number()>

=item L<avs_code()|/avs_code()>

=item L<cvv2_code()|/cvv2_code()>

=back

=head1 Settings

The following default settings exist:

=over 4

=item server

payflow.verisign.com or test-payflow.verisign.com if
test_transaction() is TRUE

=item port

443

=back

=head1 Handling of content(%content)

The following rules apply to content(%content) data:

=head2 action

If 'action' matches one of the following keys it is replaced by the
right hand side value:

  'normal authorization' => 'S', # Sale transaction
  'credit'               => 'C', # Credit (refund)
  'authorization only'   => 'A', # Authorization
  'post authorization'   => 'D', # Delayed Capture
  'void'                 => 'V',

If 'action' is 'C', 'D' or 'V' and 'order_number' is not set then
'amount', 'card_number' and 'expiration' must be set.

=head2 type

If 'type' matches one of the following keys it is replaced by the
right hand side value:

  'visa'               => 'C',
  'mastercard'         => 'C',
  'american express'   => 'C',
  'discover'           => 'C',
  'cc'                 => 'C',

The value of 'type' is used to set transaction_type().  Currently this
module only supports a transaction_type() of 'C' any other values will
cause Carp::croak() to be called in submit().

Note: Payflow Pro supports multiple credit card types, including:
American Express/Optima, Diners Club, Discover/Novus, Enroute, JCB,
MasterCard and Visa.

=head1 Setting Payflow Pro parameters from content(%content)

The following rules are applied to map data to Payflow Pro parameters
from content(%content):

      # PFP param => $content{<key>}
      VENDOR      => $self->vendor ? \( $self->vendor ) : 'login',
      PARTNER     => \( $self->partner ),
      USER        => 'login',
      PWD         => 'password',
      TRXTYPE     => 'action',
      TENDER      => 'type',
      ORIGID      => 'order_number',
      COMMENT1    => 'description',
      COMMENT2    => 'invoice_number',

      ACCT        => 'card_number',
      CVV2        => 'cvv2',
      EXPDATE     => \( $month.$year ), # MM/YY from 'expiration'
      AMT         => 'amount',

      FIRSTNAME   => 'first_name',
      LASTNAME    => 'last_name',
      NAME        => 'name',
      EMAIL       => 'email',
      COMPANYNAME => 'company',
      STREET      => 'address',
      CITY        => 'city',
      STATE       => 'state',
      ZIP         => \$zip, # 'zip' with non-alphanumerics removed
      COUNTRY     => 'country',

The required Payflow Pro parameters for credit card transactions are:

  TRXTYPE TENDER PARTNER VENDOR USER PWD ORIGID

=head1 Mapping Payflow Pro transaction responses to object methods

The following methods provides access to the transaction response data
resulting from a Payflow Pro request (after submit()) is called:

=head2 order_number()

This order_number() method returns the PNREF field, also known as the
PayPal Reference ID, which is a unique number that identifies the
transaction.

=head2 result_code()

The result_code() method returns the RESULT field, which is the
numeric return code indicating the outcome of the attempted
transaction.

A RESULT of 0 (zero) indicates the transaction was approved and
is_success() will return '1' (one/TRUE).  Any other RESULT value
indicates a decline or error and is_success() will return '0'
(zero/FALSE).

=head2 error_message()

The error_message() method returns the RESPMSG field, which is a
response message returned with the transaction result.

=head2 authorization()

The authorization() method returns the AUTHCODE field, which is the
approval code obtained from the processing network.

=head2 avs_code()

The avs_code() method returns a combination of the AVSADDR and AVSZIP
fields from the transaction result.  The value in avs_code is as
follows:

  Y     - Address and ZIP match
  A     - Address matches but not ZIP
  Z     - ZIP matches but not address
  N     - no match
  undef - AVS values not available

=head2 cvv2_code()

The cvv2_code() method returns the CVV2MATCH field, which is a
response message returned with the transaction result.

=head1 COMPATIBILITY

This module implements an interface to the Payflow Pro Perl API, which
can be downloaded at https://manager.paypal.com/ with a valid login.

=head1 AUTHORS

Ivan Kohler <ivan-payflowpro@420.am>

Phil Lobbes E<lt>phil at perkpartners.comE<gt>

Based on Business::OnlinePayment::AuthorizeNet written by Jason Kohles.

=head1 SEE ALSO

perl(1), L<Business::OnlinePayment>, L<Carp>, and the PayPal
Integration Center Payflow Pro resources at
L<https://www.paypal.com/IntegrationCenter/ic_payflowpro.html>

=cut
