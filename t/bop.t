#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 24;

use Business::OnlinePayment;

my $package = "Business::OnlinePayment";
my $driver  = "PayflowPro";

{    # new
    my $obj;

    $obj = $package->new($driver);
    isa_ok( $obj, $package );

    # convenience methods
    can_ok( $obj, qw(vendor partner) );
    can_ok( $obj, qw(order_number avs_code cvv2_response) );
    can_ok( $obj, qw(request_id debug expdate_mmyy) );

    # internal methods
    can_ok( $obj, qw(_map_fields _revmap_fields) );

    # defaults
    my $server = "payflowpro.verisign.com";

    is( $obj->server, $server, "server($server)" );
    is( $obj->port, "443", "port(443)" );
}

{    # cvv2_response / cvv2_code
    my $obj = $package->new($driver);

    my $exp = "Z";
    $obj->cvv2_response($exp);

    is( $obj->cvv2_response, $exp, "cvv2_response() is set" );
    is( $obj->cvv2_code,     $exp, "cvv2_code() calls cvv2_response" );
}

{    # client_certification_id
    my $obj = $package->new($driver);

    my $id = $obj->client_certification_id;
    isnt( $id, "", "client_certification_id() is set" );

    $id = "foo";
    is( $obj->client_certification_id($id),
        $id, "client_certification_id() can be set" );
    is( $obj->client_certification_id,
        $id, "client_certification_id() remains set" );
}

{    # client_timeout
    my $obj = $package->new($driver);

    is( $obj->client_timeout, 45, "client_timeout() returns 45 by default" );

    my $to = 60;
    is( $obj->client_timeout($to), $to, "client_timeout() can be set" );
    is( $obj->client_timeout, $to, "client_timeout() remains set" );
}

{    # expdate
    my $obj = $package->new($driver);
    my @exp = (

        #OFF [qw(1999.8   0899)],
        #OFF [qw(1984-11  1184)],
        #OFF [qw(06/7     0706)],
        #OFF [qw(06-12    1206)],
        [qw(12/06    1206)],
        [qw(6/2000   0600)],
        [qw(10/2000  1000)],
        [qw(1/99     0199)],
    );
    foreach my $aref (@exp) {
        my ( $exp, $moyr ) = @$aref;
        my ($mmyy) = $obj->expdate_mmyy($exp);
        is( $mmyy, $moyr, "$exp: MMYY '$mmyy' eq '$moyr' from $exp" );
    }
}

{    # request_id
    my $obj = $package->new($driver);

    my $id = $obj->request_id;
    isnt( $id, "", "request_id() returns something" );

    is( $obj->request_id, $id, "request_id() returns the same value" );

    $obj = $package->new($driver);
    isnt( $obj->request_id, $id, "request_id() is different for each object" );

    $id = "foo";
    is( $obj->request_id($id), $id, "request_id() can be set" );
    is( $obj->request_id, $id, "request_id() remains set" );
}
