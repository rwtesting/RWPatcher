Common perl library for generating patch files for Rimworld animal mod files (e.g. Dinosauria, Megafauna).

Unzip/Install to Mods folder (creates Mods/_lib/ directory).

    use lib "PATH-TO-Mods-DIR/_lib";
    use RWPatcher::Animals;

    my @SOURCEFILES = qw(
        path-to-sourcefile-2.xml
        path-to-sourcefile-2.xml
    );

    my %CEDATA = (

        Animal1 => {                           # Example:
            MeleeDodgeChance  => 0.09,         # required (CE only)
            MeleeCritChance   => 0.4,          # required (CE only)
            ArmorRating_Blunt => 0.1,          # optional (defaults to vanilla)
            ArmorRating_Sharp => 0.13,         # optional (defaults to vanilla)
            baseHealthScale   => 4,            # optional (defaults to vanilla)
            bodyShape         => "Quadruped",  # optional (defaults to Quadruped)
        },

        Animal 2 => {
            # etc.
        },

    );

    my $patcher;
    foreach my $sourcefile (@SOURCEFILES)
    {
        $patcher = new RWPatcher::Animals(
            sourcemod  => $NAME_OF_MOD_TO_PATCH,  # e.g. "Dinosauria"
            sourcefile => $sourcefile,
            cedata     => \%CEDATA,

            # List ParentName(s) expected for all animals to be patched, example:
            # If not even, only patch animals listed in %CEDATA.
            # Example:
            expected_parents => [ qw(AnimalThingBase AnotherParent) ],
        );

        $patcher->generate_patches();
    }

