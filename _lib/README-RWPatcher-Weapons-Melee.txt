Common perl library for generating patch files for Rimworld melee weapon mod files,
given specific CE values for each weapon.

Unzip/Install to Mods folder (creates Mods/_lib/ directory).

    use lib "path-to-lib-dir/_lib";
    use RWPatcher::Weapons::Melee;

    my @SOURCEFILES = qw(
        path-to-sourcefile-2.xml
        path-to-sourcefile-2.xml
    );

    my %CEDATA = (

        Weapon1 => {
           Bulk                    => 2,        # required
           armorPenetration => 0.3,        # optional - only used if capacity-based AP not found
           MeleeCritChance  => 0.5,        # optional - defaults to unchanged
           MeleeParryChance => 0.65,        # optional - defaults to unchanged
           weaponTags       => [qw(CE_Sidearm)], # optional - defaults to unchanged
        },

        Weapon2 => {
            # etc.
        },

    );

    my $patcher;
    foreach my $sourcefile (@SOURCEFILES)
    {
        $patcher = new RWPatcher::Weapons::Melee(
            sourcemod  => $NAME_OF_MOD_TO_PATCH,  # e.g. "Star Wars - Lightsabers"
            sourcefile => $sourcefile,
            cedata     => \%CEDATA,

            # List ParentName expected for all weapons to be patched.
            # If not even, only patch weapons listed in %CEDATA.
            # Example:
            expected_parents => [ qw(BaseMeleeWeapon BaseMeleeWeapon_Sharp) ],
        );

        $patcher->generate_patches();
    }

