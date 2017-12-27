Common perl library for generating patch files for Rimworld ranged weapon mod files,
given specific CE values for each weapon.

Unzip/Install to Mods folder (creates Mods/_lib/ directory).

    use lib "PATH-TO-Mods-DIR/_lib";
    use RWPatcher::Weapons::Melee;

    my @SOURCEFILES = qw(
        path-to-sourcefile-2.xml  # e.g. ../../918227266/Defs/WeaponDefs_Ranged/Blaster_Weps.xml
        path-to-sourcefile-2.xml
    );

    my %CEDATA = (

        Gun1 => {
            SightsEfficiency => 1,     # REQUIRED
            ShotSpread       => 0.07,  # REQUIRED
            SwayFactor       => 1.30,  # REQUIRED
            Bulk             => 6.50,  # REQUIRED
            weaponTags       => [qw(CE_AI_AssaultWeapon)],  # OPTIONAL - default unchanged
    
            # verbs changes
            defaultProjectile => 'Bullet_SWPlasmaGasCartridge',  # REQUIRED
    
            # AmmoUser from comps
            AmmoUser => {              # REQUIRED (all fields in this set)
                magazineSize => 24,
                reloadTime   => 3,
                ammoSet      => 'AmmoSet_SWPlasmaGasCartridge',
            },
    
            # FireModes from comps
            FireModes => {             # OPTIONAL (all fields in this set) - default unchanged
                aimedBurstShotCount => 3,
                aiUseBurstMode      => 'TRUE',
                aiAimMode           => 'AimedShot',
            },
        },

        Gun2 => {
            # etc.
        },

    );

    my $patcher;
    foreach my $sourcefile (@SOURCEFILE)
    {
        $patcher = new RWPatcher::Weapons::Ranged(
            sourcemod  => $NAME_OF_MOD_TO_PATCH,  # e.g. "High Caliber"
            sourcefile => $sourcefile,
            cedata     => \%CEDATA,
        );

        $patcher->generate_patches();
    }

