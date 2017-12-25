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

    my $patcher = new RWPatcher::Animals(
        sourcemod   => $NAME_OF_MOD_TO_PATCH,  # e.g. "Dinosauria"
        sourcefiles => \@SOURCEFILES,
        cedata      => \%CEDATA,
    );

    $patcher->generate_patches();

