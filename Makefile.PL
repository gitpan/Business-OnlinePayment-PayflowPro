use ExtUtils::MakeMaker;
# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    'NAME'         => 'Business::OnlinePayment::PayflowPro',
    'VERSION_FROM' => 'PayflowPro.pm', # finds $VERSION
    'AUTHOR'       => 'Ivan Kohler <ivan-payflowpro@420.am>',
    'PREREQ_PM'    => { 'Business::OnlinePayment' => 0,
                        'PFProAPI' => 0,
                      },
    #'NORECURS'     => 1, # dont descend into subdirectories
);
