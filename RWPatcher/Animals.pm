package RWPatcher::Animals;

# Generate patch files for animal mod file(s) (e.g. Dinosauria).

use RWPatcher;
use parent "RWPatcher";

# Source file name format:
# For each, patch file will be ./<base-dir-name>/<file.xml>
# Source may end with (-REF)?.(txt|xml), which will be replaced with ".xml".
#   e.g. Source = my-path/Races/Dinosauria.xml
#        Patch  = ./Races/Dinosauria.xml

# DEFAULT values not in source xml from Dinosauria
my %DEFAULT = (
    bodyShape => "Quadruped",
    #MeleeDodgeChance => 0.08,	# Elephant
    #MeleeCritChance  => 0.79,	# Elephant
);

# armor types to check (if not defined, don't patch - fallback to source mod values).
my @ARMORTYPES = qw(ArmorRating_Blunt ArmorRating_Sharp);

# armor penetration DEFAULT per bodypart
my $DEFAULT_AP = 0.15;		# default ap for unlisted bodyparts
my %DEFAULT_AP = (
    HeadAttackTool => 0.13,	# Elephant
    TailAttackTool => 0.17,	# (like a leg?)

    HornAttackTool => 0.457,	# Thrumbo (should differentiate between horncut/hornstab)
    Teeth          => 0.3,	# Gigantopithecus
    Beak           => 0.3,	# Titanis
    Mouth          => 0.2,	# Arthropleura

    LeftLeg        => 0.17,
    RightLeg       => 0.17,
    FrontLeftLeg   => 0.17,	# Elephant
    FrontRightLeg  => 0.17,	# Elephant

    LeftHand       => 0.3,	# Gigantopithecus
    RightHand      => 0.3,	# Gigantopithecus
    FrontLeftPaw   => 0.25,	# Doedicurus
    FrontRightPaw  => 0.25,	# Doedicurus

    LeftLegClawAttackTool  => 0.227,	# Megascarab headclaw
    RightLegClawAttackTool => 0.227,	# Megascarab headclaw
    LeftArmClawAttackTool  => 0.227,	# Megascarab headclaw
    RightArmClawAttackTool => 0.227,	# Megascarab headclaw

);

# Constructor
#
# Params:
# - sourcemod   - (string) If given, patch won't apply unless this mod is loaded
# - sourcefiles - \@source_file_paths
# - cedata      - Combat Extended data for each animal to be patched,
#                 { [ anim1 => \%data ], ... }
# Example cedata:
# {
#     Entelodont => {
#         MeleeDodgeChance  => 0.2,		# required
#         MeleeCritChance   => 0.5,		# required
#         ArmorRating_Blunt => 0.1,		# optional
#         ArmorRating_Sharp => 0.125,		# optional
# 	  bodyShape         => "Quadruped",	# optional
# 	  baseHealthScale   => 7,		# optional
#     },
#     ...
# }
#
# Throw exception on error.
#     
sub new
{
    my($class, %params) = @_;

    my %VALIDPARAMS = (
        MeleeDodgeChance  => { required => 1, type => "" },
        MeleeCritChance   => { required => 1, type => "" },
        ArmorRating_Blunt => { required => 0, type => "" },
        ArmorRating_Sharp => { required => 0, type => "" },
        bodyShape         => { required => 0, type => "" },
        baseHealthScale   => { required => 0, type => "" },
    );

    # Base handles parameter validation + initialization
    return $class->SUPER::new(params => \%params, validator => \%VALIDPARAMS);
}

# Get/Set expected parent class of animal defs.
# This is how we determine which defs to patch.
#
# For more complex criteria, overwrite is_elem_patchable() method.
#
sub expected_parent
{
    my($self, $parentname) = @_;

    $self->{expected_parent_class} = $parentname if ($parentname);
    return $self->{expected_parent_class} || "AnimalThingBase";
}

# Should this xml child element be patched?
# Return:
#   - $defName - yes, patchable
#   - undef - don't patch
#
sub is_elem_patchable
{
    my($self, $thiselem) = @_;

    my $defname = $thiselem->{defName};
    return defined $defname && $thiselem->{ParentName} eq $self->expected_parent() ? $defname : undef;
}

# Generate patch files for this patcher
sub generate_patches
{
    my($self) = @_;


    # Make sure output dirs are created before trying to write any patches
    $self->__setup_patch_dirs();

    # Patch each source file
    my($elem, $patchable, $tool, $ap, $bodyshape, $armortype, $statbases, $tag);
    foreach my $sourcefile (@{$self->{sourcefiles}})
    {

    # Open source/output files
    $self->__info("Source - $sourcefile");
    $self->__info("Patch  - " . $self->__init_patchfile($sourcefile));
    $self->__init_sourcexml($sourcefile);

    $self->__print_patch_header();

    $self->__print_sourcemod_check();

    # Step through source xml.
    # Generate a template for each $patchable found.
    # If entity is found that we don't have CE values for, warn and skip.
    #
    # Perf:
    # - Use one sequence per file to reduce load times, short circuit.
    # - Load times: Defs/ThingDef < /Defs/ThingDef << */ThingDef/ <<< //ThingDef/
    #
    foreach $elem ( @{$self->{sourcexml}->{ThingDef}} )
    {
        # Skip non-entities and unknown entities
        next unless defined( $patchable = $self->is_elem_patchable($elem) );

        if (!exists $self->{cedata}->{$patchable})
        {
            $self->__warn(<<EOF);
WARN: New or unknown entity found. Skipping because no CE data:

Name: $patchable
Desc:
$elem->{description}

EOF
            next;
        }

        # Start patch
        $self->__print_patch(<<EOF);
    <!-- ========== $patchable ========== -->

EOF

        # Add bodyShape
        $bodyshape = $self->{cedata}->{$patchable}->{bodyShape} || $DEFAULT{bodyShape};
        $self->__print_patch(<<EOF);
    <li Class="PatchOperationAddModExtension">
    <xpath>Defs/ThingDef[defName="$patchable"]</xpath>
    <value>
        <li Class="CombatExtended.RacePropertiesExtensionCE">
            <bodyShape>$bodyshape</bodyShape>
        </li>
    </value>
    </li>

EOF

        # For each bodypartgroup listed for this entity, add CE attribute + armor pen value
        if ($elem->{tools}->{li})
        {
	    $self->__print_patch(<<EOF);
    <!-- Patch $patchable : Tools / Verbs -->

EOF
            foreach $tool ( @{ $elem->{tools}->{li} } )
            {
                $ap = $DEFAULT_AP{$tool->{linkedBodyPartsGroup}} || $DEFAULT_AP;
	        $tag = $tool->{id} ? "id" : "linkedBodyPartsGroup"; # rare case where 2 entries for same bodypart, different id (e.g. Megafauns hornScratch/hornBlunt are both HornAttackTool).
                $self->__print_patch(<<EOF);
    <li Class="PatchOperationAttributeSet">
    <xpath>Defs/ThingDef[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]</xpath>
        <attribute>Class</attribute>
        <value>CombatExtended.ToolCE</value>
    </li>

    <li Class="PatchOperationAdd">
    <xpath>Defs/ThingDef[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]</xpath>
    <value>
        <armorPenetration>$ap</armorPenetration>
    </value>
    </li>

EOF

	        # HACK: temp remove surpriseattack stun nodes - CE v0.18.0.2 beta
	        # throws parry / armor pen error here (null object).
	        if (exists $tool->{surpriseAttack})
	        {
                    $self->__print_patch(<<EOF);
    <!-- HACK: temporarily remove stun nodes to prevent CE v0.18.0.2 beta null object error -->
    <li Class="PatchOperationRemove">
    <xpath>Defs/ThingDef[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]/surpriseAttack</xpath>
    </li>

EOF
	        }
            }
        }

        # Adjust stats
        $self->__print_patch(<<EOF);
    <!-- Patch $patchable : Stats -->

EOF

        # Add baseHealthScale
        if (exists $self->{cedata}->{$patchable}->{baseHealthScale})
        {
            $self->__print_patch(<<EOF);

    <li Class="PatchOperationReplace">
    <xpath>Defs/ThingDef[defName="$patchable"]/race/baseHealthScale</xpath>
    <value>
        <baseHealthScale>$self->{cedata}->{$patchable}->{baseHealthScale}</baseHealthScale>
    </value>
    </li>

EOF
        }


        # statBases: Dodge / Crit
        $statbases = <<EOF;
    <!-- Patch statBases last so that we know all previous sequence entries succeeded.
         These values are easy to check in-game. -->
    <li Class="PatchOperationAdd">
    <xpath>Defs/ThingDef[defName="$patchable"]/statBases</xpath>
    <value>
        <MeleeDodgeChance>$self->{cedata}->{$patchable}->{MeleeDodgeChance}</MeleeDodgeChance>
        <MeleeCritChance>$self->{cedata}->{$patchable}->{MeleeCritChance}</MeleeCritChance>
EOF

        # statBases: armor values (if undefined, fallback to core)
        foreach $armortype (@ARMORTYPES)
        {
            if (exists $self->{cedata}->{$patchable}->{$armortype})
	    {
	        $statbases = $statbases . <<EOF;
        <$armortype>$self->{cedata}->{$patchable}->{$armortype}</$armortype>
EOF
	    }
        }

        # Add all (defined) statBases
        $self->__print_patch(<<EOF);
$statbases
    </value>
    </li>

EOF

    }

    # Closer
    $self->__print_patch_closer();
    $self->__close_patchfile();

    }  # end foreach source file

    return 1; # success
}  # end generate_patches()

1;

__END__

