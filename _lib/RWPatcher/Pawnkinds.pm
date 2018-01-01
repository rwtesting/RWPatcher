package RWPatcher::Pawnkinds;

# Generate patch files for pawnkind mod file(s).
#
# Patch any pawnkinds with one of:
# - The expected ParentName
# - Defined in CEDATA

use RWPatcher;
use parent "RWPatcher";

#
# Ammo in inventory at spawn:
# - Define default min/max for all pawnkinds patched.
# - Define exceptions (e.g. more ammo on archers/bosses) to overwrite default..
#

# Min/Max ammo at spawn if undefined by caller
my $DEF_AMMO_MIN = 3;
my $DEF_AMMO_MAX = 5;

# Constructor
#
# Required parameters:
# - sourcefile  - (string) $source_file_paths
# - cedata      - (hashref) Combat Extended data for each entity to be patched,
#                 { [ entity1 => \%data ], ... }
#
# Optional parameters:
# - AmmoMin     - (int) Default min ammo (overwrite for specific pawns in cedata)
# - AmmoMax     - (int) Default min ammo (overwrite for specific pawns in cedata)
# - sourcemod  => (string) Don't apply patch unless this mod is loaded.
# - patchdir   => (string) write patches to this dir (default: auto-use name of immediate parent dir of sourcefile)
# - expected_parents => (string/array-ref)
#                If given, patch only ThingDefs with this ParentName.
#                If multiple(array-ref), element must match one of the listed ParentName(s).
#                If not given, patch only defs with defName in cedata.
#                Specifying parent_thing will identify new entries in source xml that
#                are not defined in cedata.
#
#
# Example cedata:
# {
#     ImpArcher => {
#         AmmoMin => 10,  # overwrites default min_ammo
#         AmmoMax => 12,  # overwrites default max_ammo
#     },
#     RebArcher => {
#         AmmoMin => 10,
#         AmmoMax => 12,
#     },
#     # etc.
# }
#
# Throw exception on error.
#     
sub new
{
    my($class, %params) = @_;

    my %VALIDPARAMS = (
        AmmoMin => { required => 0, type => "" },
        AmmoMax => { required => 0, type => "" },
    );

    # Base handles parameter validation + initialization
    my $self = $class->SUPER::new(params => \%params, validator => \%VALIDPARAMS);

    $self->{AmmoMin} = $params{AmmoMin} if defined $params{AmmoMin};
    $self->{AmmoMax} = $params{AmmoMax} if defined $params{AmmoMax};
    $self->base_node_name("PawnKindDef");

    return $self;
}

# Generate patch files for this patcher
sub generate_patches
{
    my($self) = @_;

    # Init and Header
    $self->__start_patch();

    # Step through source xml.
    # Generate a template for each $patchable found.
    my($patchable, $ammo_min, $ammo_max);
    foreach my $elem ( @{$self->{sourcexml}->{PawnKindDef}} )
    {
        # Skip non-entities and unknown entities
        next unless $self->is_elem_patchable($elem);
	$patchable = $elem->{defName};
	$ammo_min = eval { $self->{cedata}->{$patchable}->{AmmoMin} } || $self->{AmmoMin} || $DEF_AMMO_MIN;
	$ammo_max = eval { $self->{cedata}->{$patchable}->{AmmoMax} } || $self->{AmmoMax} || $DEF_AMMO_MAX;

        # Start patch
        $self->__print_patch(<<EOF);
    <!-- ========== $patchable ========== -->

    <li Class="PatchOperationAddModExtension">
    <xpath>Defs/PawnKindDef[defName="$patchable"]</xpath>
    <value>
        <li Class="CombatExtended.LoadoutPropertiesExtension">
            <primaryMagazineCount>
                <min>$ammo_min</min>
                <max>$ammo_max</max>
            </primaryMagazineCount>
        </li>
    </value>
    </li>

EOF
    }

    $self->__end_patch();
}

1;

__END__

