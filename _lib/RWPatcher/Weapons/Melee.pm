package RWPatcher::Weapons::Melee;

use RWPatcher;
use parent "RWPatcher";

# Generate patch files for melee weapon mod files (e.g. Star Wars Lightsabers).
# - add weapon bulk
# - add armor penetration (tools nodes)
# - add EC attribute to tools node entries
# - add CE weapon tags
# - add melee crit/parry chance as offsets (same as CE patches for core melee weapons)
# ? Do I need to do something with deflection?
#
# Write results to related patch files (overwrite existing).
#
# Warn+Skip if weapon found in sourcefile that we don't have CE data for.
#
# Armor Penetration
#   - In a17 was per-weapon
#   - In b18 is per tools item
# For b18, we'll set armor pen based on tool capacity and default to a17 value
# only if tool capacity can't be determined/mapped.
#

# Armor Penetration per tool capacity
# (to start, we'll use similar values from core patch with bonus for vibro capacities)
#
# To be more realistic, AP would be per-weapon and per-capacity.
# For example, a formula for Axe+VibroCut(more), Axe+VibroStab, Staff+VibroCut(less), etc.
# We could also take the a17 values and adjust them by capacity (+stab, -blunt, =cut?).
# Not really needed for this patch.
# (It would be a lot easier w/ less load time to apply a17 AP value to all tools entries)
#
my %AP = (
    Cut		 => 0.201,	# longsword
    Stab	 => 0.304,	# longsword
    Blunt	 => 0.087,	# longsword
    PJ_VibroCut	 => 0.231,	# longsword * 1.15
    PJ_VibroStab => 0.350,	# longsword * 1.15
    PJ_SaberCut  => 0.231,	# longsword * 1.15
    PJ_SaberStab => 0.350,	# longsword * 1.15
);

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
#      PJ_Vibroaxe => {
#          Bulk		    => 2,	# required
#  	   armorPenetration => 0.3,	# optional - only used if capacity-based AP not found
#  	   MeleeCritChance  => 0.5,	# optional - defaults to unchanged
#  	   MeleeParryChance => 0.65,	# optional - defaults to unchanged
#  	   weaponTags       => [qw(CE_Sidearm)], # optional - defaults to unchanged
#      },
#      # etc.
# }
#
# Throw exception on error.
#     
sub new
{
    my($class, %params) = @_;
    $params{base_node_name} = "ThingDef";

    my %VALIDPARAMS = (
        Bulk		 => { required => 1, type => "" },
  	armorPenetration => { required => 0, type => "" },
  	MeleeCritChance  => { required => 0, type => "" },
  	MeleeParryChance => { required => 0, type => "" },
  	weaponTags       => { required => 0, type => "ARRAY" },
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
    # Generate patch for each known defName/weapon in the same order.
    my($weapon, $data, $key, $val, $ref);
    foreach my $elem ( @{$self->{sourcexml}->{ThingDef}} )
    {
        # Skip non-entities and unknown entities
        next unless $self->is_elem_patchable($elem);
	$patchable = $elem->{defName};

        $weapon = $elem->{defName};
        $data = $self->{cedata}->{$elem->{defName}};
    
        # Add CE bulk
        $self->__print_patch(<<EOF);

        <!-- ========== $weapon ========== -->

	<li Class="PatchOperationAdd">
	    <xpath>Defs/ThingDef[defName="$weapon"]/statBases</xpath>
	    <value>
                <Bulk>$data->{Bulk}</Bulk>
	    </value>
	</li>

EOF

        # Add CE weapon tags
        if (exists $data->{weaponTags})
        {
            $self->__print_patch(<<EOF);
        <!-- Insert CE weapon tags. Create node if needed -->
	<li Class="PatchOperationSequence">
  	<success>Always</success>
  	<operations>
    	    <li Class="PatchOperationTest">
      	        <xpath>Defs/ThingDef[defName="$weapon"]/weaponTags</xpath>
      	        <success>Invert</success>
    	    </li>
    	    <li Class="PatchOperationAdd">
      	        <xpath>Defs/ThingDef[defName="$weapon"]</xpath>
      	            <value>
        	        <weaponTags />
      	            </value>
    	    </li>
  	</operations>
	</li>

	<li Class="PatchOperationAdd">
	    <xpath>Defs/ThingDef[defName="$weapon"]/weaponTags</xpath>
	    <value>
EOF
            foreach $key (@{$data->{weaponTags}})
            {
                $self->__print_patch(<<EOF);
                <li>$key</li>
EOF
	    }

            $self->__print_patch(<<EOF);
	    </value>
	</li>

EOF
        }

        # Add CE attribute to tools node entries
        $self->__print_patch(<<EOF);
	<!-- Add CE attribute to all tools entries -->
	<li Class="PatchOperationAttributeSet">
	    <xpath>Defs/ThingDef[defName="$weapon"]/tools/li</xpath>
	    <attribute>Class</attribute>
	    <value>CombatExtended.ToolCE</value>
	</li>

EOF
        # Add armor penetration to all tools entries
        if (exists $elem->{tools} && exists $elem->{tools}->{li})
        {
	    foreach $ref ( @{$elem->{tools}->{li}} )
	    {
                # AP based on capacity (default to a17 value || 0.01)
	        $key = $ref->{capacities}->{li}->[0];
	        $val = $key && $AP{$key} ? $AP{$key} : ($data->{armorPenetration} || 0);
                $self->__print_patch(<<EOF);
	<li Class="PatchOperationAdd">
	    <xpath>Defs/ThingDef[defName="$weapon"]/tools/li[label="$ref->{label}"]</xpath>
	    <value>
		<armorPenetration>$val</armorPenetration>
	    </value>
	</li>

EOF
            }
        }

        # Add crit/parry chances as offsets
        # Add this last so that we can verify in-game that all previous sequence elements
        # were successful (check these attributes on weapons).
	$val = "";
	$val .= <<EOF if exists $data->{MeleeCritChance};
                     <MeleeCritChance>$data->{MeleeCritChance}</MeleeCritChance>
EOF
	$val .= <<EOF if exists $data->{MeleeParryChance};
                     <MeleeParryChance>$data->{MeleeParryChance}</MeleeParryChance>
EOF
        if ($val)
	{
	    $self->__print_patch(<<EOF);
	 <!-- Crit/Parry chances, modeled after CE patches for core melee weapons -->
         <li Class="PatchOperationAdd">
             <xpath>Defs/ThingDef[defName="$weapon"]</xpath>
             <value>
                 <equippedStatOffsets>
$val
                 </equippedStatOffsets>
             </value>
         </li>

EOF
        }
    }

    $self->__end_patch();

    return 1;  # success
}

1;

__END__

