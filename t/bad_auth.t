BEGIN { $| = 1; print "1..1\n"; }

use Business::OnlinePayment;

my $tx = new Business::OnlinePayment("PayflowPro",
    #'vendor'    => 'your_vendor',
    'partner'   => 'verisign',
    'cert_path' => '/home/ivan/Business-OnlinePayment-PayflowPro.docs/verisign/payflowpro/linux/certs/',
);

$tx->content(
    type           => 'VISA',
    login          => 'test231',
    password       => '231test',
    action         => 'Normal Authorization',
    description    => 'Business::OnlinePayment::PayflowPro visa test',
    amount         => '0.01',
    first_name     => 'Tofu',
    last_name      => 'Beast',
    address        => '123 Anystreet',
    city           => 'Anywhere',
    state          => 'UT',
    zip            => '84058',
    country        => 'US',
    email          => 'ivan-payflowpro@420.am',
    #card_number    => '4007000000027',
    #card_number    => '4111111111111111',
    card_number    => '4111111111111112',
    expiration     => '12/2004',
);

$tx->test_transaction(1);

$tx->submit();

if($tx->is_success()) {
    print "not ok 1\n";
    $auth = $tx->authorization;
    warn "********* $auth ***********\n";
} else {
    print "ok 1\n";
    warn '***** '. $tx->error_message. " *****\n";
    exit;
}

