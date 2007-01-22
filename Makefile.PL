use ExtUtils::MakeMaker;

# See lib/ExtUtils/MakeMaker.pm for details of how to influence
# the contents of the Makefile that is written.
WriteMakefile(
    NAME         => 'Business::OnlinePayment::PayflowPro',
    VERSION_FROM => 'PayflowPro.pm',
    PREREQ_PM    => {
        Business::OnlinePayment => 0,
        PFProAPI                => 0,
    },
    (
        $] >= 5.005
        ?    ## Add these new keywords supported since 5.005
          (
            ABSTRACT_FROM => 'PayflowPro.pm',
            AUTHOR        => 
                join(
                     ' and ',
                     'Ivan Kohler <ivan-payflowpro@420.am>',
                     'Phil Lobbes <phil at perkpartners.com>',
                    ),
          )
        : ()
    ),
);
