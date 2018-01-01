package RWPatcher::Weapons::Ranged;

use RWPatcher;
use parent "RWPatcher";

#
# Generate CE patch for given ranged weapon mod file(s):
# - Add missing CE values
# - Add <tools> node (gun melee values, use the same values for all blasters for now).
# - Verbatim copy <verbs> node to new CE <Properties> node.
#   (tried renaming <verbs> to Properties + changes, but <verbs> needs to remain)
#   (can't find a built-in method for copying a node via operations)
#
# Write results to associated patch file(s) (overwrite existing).
#
# Warn+Skip if gun found in source file that we don't have CE data for.
#

# Common values for all guns
my $VERBCLASS = 'CombatExtended.Verb_ShootCE';

# Constructor
#
# Required parameters:
# - sourcefile  - (string) $source_file_paths
# - cedata      - (hashref) Combat Extended data for each entity to be patched,
#                 { [ entity1 => \%data ], ... }
#
# Optional parameters:
# - sourcemod  => (string) Don't apply patch unless this mod is loaded.
# - patchdir   => (string) write patches to this dir (default: auto-use name of immediate parent dir of sourcefile)
# - expected_parents => (string/array-ref)
#                If given, patch only ThingDefs with this ParentName.
#                If multiple(array-ref), element must match one of the listed ParentName(s).
#                If not given, patch only defs with defName in cedata.
#                Specifying parent_thing will identify new entries in source xml that
#                are not defined in cedata.
#
# Throw exception on error.
#
# Example cedata:
#    %cedata = (
#
#        Gun1 => {
#            SightsEfficiency => 1,     # REQUIRED
#            ShotSpread       => 0.07,  # REQUIRED
#            SwayFactor       => 1.30,  # REQUIRED
#            Bulk             => 6.50,  # REQUIRED
#            weaponTags       => [qw(CE_AI_AssaultWeapon)],  # OPTIONAL - default unchanged
#    
#            # verbs changes
#            defaultProjectile => 'Bullet_SWPlasmaGasCartridge',  # REQUIRED
#    
#            # AmmoUser from comps
#            AmmoUser => {              # REQUIRED (all fields in this set)
#                magazineSize => 24,
#                reloadTime   => 3,
#                ammoSet      => 'AmmoSet_SWPlasmaGasCartridge',
#            },
#    
#            # FireModes from comps
#            FireModes => {             # OPTIONAL (all fields in this set) - default unchanged
#                aimedBurstShotCount => 3,
#                aiUseBurstMode      => 'TRUE',
#                aiAimMode           => 'AimedShot',
#            },
#        },
#     
sub new
{
    my($class, %params) = @_;
    $params{base_node_name} = "ThingDef";

    # Expected parameters
    my %VALIDPARAMS = (
        SightsEfficiency  => { required => 1, type => "" },
        ShotSpread        => { required => 1, type => "" },
        SwayFactor        => { required => 1, type => "" },
        Bulk              => { required => 1, type => "" },
        weaponTags        => { required => 0, type => "ARRAY" },
        defaultProjectile => { required => 1, type => "" },
        AmmoUser          => { required => 1, type => "HASH" },
        FireModes         => { required => 0, type => "HASH" },
    );

    # Base handles parameter validation + initialization
    return $class->SUPER::new(params => \%params, validator => \%VALIDPARAMS);
}

# Generate patch files for this patcher
sub generate_patches
{
    my($self) = @_;

    $self->__start_patch();

    # Step through source xml.
    # Generate patch for each known weapon/$nametag (in the same order as source).
    my($nametag, $xpathname, $data, $key);
    foreach my $elem ( @{$self->{sourcexml}->{ThingDef}} )
    {
        # Skip non-entities and unknown entities
        next unless $self->is_elem_patchable($elem);
	$nametag = $self->__nametag($elem);
	$xpathname = $self->__xpathname($elem);
        $data = $self->{cedata}->{$nametag};

        $self->__print_patch(<<EOF);
    <!-- ========== $nametag ========== -->

    <!-- Create tools node if it doesn't exist -->
    <li Class="PatchOperationSequence">
        <success>Always</success>
        <operations>
            <li Class="PatchOperationTest">
            <xpath>Defs/ThingDef[$xpathname]/tools</xpath>
                <success>Invert</success>
            </li>
            <li Class="PatchOperationAdd">
            <xpath>Defs/ThingDef[$xpathname]</xpath>
                <value>
                      <tools />
                </value>
            </li>
        </operations>
    </li>

    <!-- Add tools melee values -->
    <li Class="PatchOperationAdd">
        <xpath>Defs/ThingDef[$xpathname]/tools</xpath>
        <value>
            <li Class="CombatExtended.ToolCE">
                <label>stock</label>
                <capacities>
                    <li>Blunt</li>
                </capacities>
                <power>9</power>
                <cooldownTime>1.8</cooldownTime>
                <commonality>1.5</commonality>
                <armorPenetration>0.11</armorPenetration>
                <linkedBodyPartsGroup>Stock</linkedBodyPartsGroup>
            </li>
            <li Class="CombatExtended.ToolCE">
                <id>barrelblunt</id>
                <label>barrel</label>
                <capacities>
                    <li>Blunt</li>
                </capacities>
                <power>10</power>
                <cooldownTime>1.9</cooldownTime>
                <armorPenetration>0.118</armorPenetration>
                <linkedBodyPartsGroup>Barrel</linkedBodyPartsGroup>
            </li>
            <li Class="CombatExtended.ToolCE">
                <id>barrelpoke</id>
                <label>barrel</label>
                <capacities>
                    <li>Poke</li>
                </capacities>
                <power>10</power>
                <cooldownTime>1.9</cooldownTime>
                <armorPenetration>0.086</armorPenetration>
                <linkedBodyPartsGroup>Barrel</linkedBodyPartsGroup>
            </li>
        </value>
    </li>

    <!-- CE conversion -->
    <li Class="CombatExtended.PatchOperationMakeGunCECompatible">
        <defName>$nametag</defName>
        <statBases>
            <Bulk>$data->{Bulk}</Bulk>
            <SightsEfficiency>$data->{SightsEfficiency}</SightsEfficiency>
            <ShotSpread>$data->{ShotSpread}</ShotSpread>
            <SwayFactor>$data->{SwayFactor}</SwayFactor>
        </statBases>
EOF

        # Add weapon tags from both source xml and CE data, if any
        #%union = map {$_ => 1} (exists $elem->{weaponTags} ? @{$elem->{weaponTags}->{li}} : (), exists $data->{weaponTags} ? @{$data->{weaponTags}} : ());
        if (exists $data->{weaponTags})
        {
            $self->__print_patch(<<EOF);
        <weaponTags>
EOF
             foreach $key ( @{$data->{weaponTags}} )
             {
                 $self->__print_patch(<<EOF);
              <li>$key</li>
EOF
             }

             $self->__print_patch(<<EOF);
        </weaponTags>
EOF
        }

        # Add AmmoUser (CE only)
        if (exists $data->{AmmoUser})
        {
            $self->__print_patch(<<EOF);
        <AmmoUser>
EOF
	    # sort keys so that fields are in defined order for diffs
	    foreach $key (sort keys %{$data->{AmmoUser}})
            {
            $self->__print_patch(<<EOF);
              <$key>$data->{AmmoUser}->{$key}</$key>
EOF
            }
            $self->__print_patch(<<EOF);
        </AmmoUser>
EOF
        }

        # Add FireModes (CE only)
        if (exists $data->{FireModes})
        {
            $self->__print_patch(<<EOF);
        <FireModes>
EOF
	    # sort keys so that fields are in defined order for diffs
	    foreach $key (sort keys %{$data->{AmmoUser}})
            {
            $self->__print_patch(<<EOF);
             <$key>$data->{FireModes}->{$key}</$key>
EOF
            }
            $self->__print_patch(<<EOF);
        </FireModes>
EOF
        }

        # Closer: CombatExtended.PatchOperationMakeGunCECompatible
        $self->__print_patch(<<EOF);
    </li>

EOF

        # Update verbs node. Don't use Properties in PatchOperationMakeGunCECompatible
        # because we don't want to copy the entire verbs node over.
        if (exists $elem->{verbs} )
        {
            $self->__print_patch(<<EOF);
    <li Class="PatchOperationAttributeSet">
    <xpath>Defs/ThingDef[$xpathname]/verbs/li</xpath>
        <attribute>Class</attribute>
        <value>CombatExtended.VerbPropertiesCE</value>
    </li>

    <li Class="PatchOperationReplace">
    <xpath>Defs/ThingDef[$xpathname]/verbs/li/verbClass</xpath>
    <value>
        <verbClass>$VERBCLASS</verbClass>
    </value>
    </li>

    <li Class="PatchOperationReplace">
    <xpath>Defs/ThingDef[$xpathname]/verbs/li/defaultProjectile</xpath>
    <value>
        <defaultProjectile>$data->{defaultProjectile}</defaultProjectile>
    </value>
    </li>

EOF
         }
    }

    # Closer
    $self->__end_patch();

    return 1; # success
}

1;

__END__

