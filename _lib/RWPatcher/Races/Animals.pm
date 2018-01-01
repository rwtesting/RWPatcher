package RWPatcher::Races::Animals;

# Generate patch files for animal mod file(s) (e.g. Dinosauria).

use RWPatcher::Races;
use parent "RWPatcher::Races";

$RWPatcher::Races::DEFAULT{bodyShape} = "Quadruped";

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
    $params{base_node_name} = "ThingDef";

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

1;

__END__

