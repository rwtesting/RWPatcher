package RWPatcher::Races::AlienRaces;

# Generate patch files for alien races mod files (mods based on Erdelf's base)

use RWPatcher::Races;
use parent "RWPatcher::Races";

# Use core humanoid values
$RWPatcher::Races::DEFAULT{bodyShape} = "Humanoid";
$RWPatcher::Races::TOOLAP{HeadAttackTool}->{Blunt} = 0.079;
$RWPatcher::Races::TOOLAP{LeftHand}->{Blunt} = 0.095;
$RWPatcher::Races::TOOLAP{RightHand}->{Blunt} = 0.095;

# Source file name format:
# For each, patch file will be ./<base-dir-name>/<file.xml>
# Source may end with (-REF)?.(txt|xml), which will be replaced with ".xml".
#   e.g. Source = my-path/Races/Dinosauria.xml
#        Patch  = ./Races/Dinosauria.xml

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
    $params{base_node_name} = "AlienRace.ThingDef_AlienRace";

    my %VALIDPARAMS = (
        MeleeDodgeChance  => { required => 0, type => "" },
        MeleeCritChance   => { required => 0, type => "" },
        ArmorRating_Blunt => { required => 0, type => "" },
        ArmorRating_Sharp => { required => 0, type => "" },
        bodyShape         => { required => 0, type => "" },
        baseHealthScale   => { required => 0, type => "" },
    );

    # Base handles parameter validation + initialization
    return $class->SUPER::new(params => \%params, validator => \%VALIDPARAMS);
}

# Insert patch nodes for this class
# (insert early in sequence so that verify success by checking later parent changes in-game)
sub __generate_patches_first
{
    my($self, $curelem) = @_;
    my $xpathname = $self->__xpathname($curelem);

    # CE additions for weapon-wielding pawns
    $self->__print_patch(<<EOF);
    <!-- Add comps node if it doesn't exist -->
    <li Class="PatchOperationSequence">
    <success>Always</success>
    <operations>
        <li Class="PatchOperationTest">
        <xpath>/Defs/AlienRace.ThingDef_AlienRace[$xpathname]/comps</xpath>
            <success>Invert</success>
        </li>
        <li Class="PatchOperationAdd">
        <xpath>/Defs/AlienRace.ThingDef_AlienRace[$xpathname]</xpath>
        <value>
            <comps />
        </value>
        </li>
    </operations>
    </li>

    <li Class="PatchOperationAdd">
    <xpath>/Defs/AlienRace.ThingDef_AlienRace[$xpathname]/comps</xpath>
        <value>
            <li>
                <compClass>CombatExtended.CompPawnGizmo</compClass>
            </li>
            <li Class="CombatExtended.CompProperties_Suppressable" />
        </value>
    </li>

EOF
}

1;

__END__

