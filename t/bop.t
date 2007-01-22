#!/usr/bin/perl

use strict;
use warnings;
use Test::More tests => 6;

use Business::OnlinePayment;

my $package = "Business::OnlinePayment";
my $driver  = "PayflowPro";

{    # new
    my $obj;

    $obj = $package->new($driver);
    isa_ok( $obj, $package );

    # new (via build_subs) automatically creates convenience methods
    can_ok( $obj, qw(vendor partner cert_path) );
    can_ok( $obj, qw(order_number avs_code cvv2_code) );

    # defaults
    my $server = "payflow.verisign.com";

    is( $obj->server,    $server, "server($server)" );
    is( $obj->port,      "443",   "port(443)" );
    is( $obj->cert_path, undef,   "cert_path" );
}
