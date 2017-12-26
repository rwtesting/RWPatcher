Common perl library for generating patch files for Rimworld melee weapon mod files,
given specific CE values for each weapon.

Unzip/Install to Mods folder (creates Mods/_lib/ directory).

    use lib "PATH-TO-Mods-DIR/_lib";
    use RWPatcher::Weapons::Melee;

    my @SOURCEFILES = qw(
        path-to-sourcefile-2.xml
        path-to-sourcefile-2.xml
    );

    my %CEDATA = (

        Weapon1 => {
           Bulk        	    => 2,	# required
           armorPenetration => 0.3,	# optional - only used if capacity-based AP not found
           MeleeCritChance  => 0.5,	# optional - defaults to unchanged
           MeleeParryChance => 0.65,	# optional - defaults to unchanged
           weaponTags       => [qw(CE_Sidearm)], # optional - defaults to unchanged
        },

        Weapon2 => {
            # etc.
        },

    );

    my $patcher = new RWPatcher::Animals(
        sourcemod   => $NAME_OF_MOD_TO_PATCH,  # e.g. "Star Wars - Lightsabers"
        sourcefiles => \@SOURCEFILES,
        cedata      => \%CEDATA,
    );

    $patcher->generate_patches();

