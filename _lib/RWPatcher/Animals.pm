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

# Armor types to check (if not defined, don't patch - fallback to source mod values).
my @ARMORTYPES = qw(ArmorRating_Blunt ArmorRating_Sharp);

# Armor penetration per bodypart
#
# TODO: Simplify this by approximating all AP by capacity, ignore bodypartgroup,
#       and allow caller/child to specify exceptions per entity+bodypart+capacity.
#
my $DEFAULT_AP = 0.15;  # default ap for unlisted bodyparts/capacities
my %TOOLAP = (
    HeadAttackTool => { Blunt => 0.133, Scratch => 0.077 },  # Elephant
    TailAttackTool => { Blunt => 0.17, Scratch => 0.077 },   # (like a leg?)

    HornAttackTool => { Cut => 0.243, Stab => 0.457, Blunt => 0.221, Scratch => 0.077},	# Thrumbo, Rhino(B)
    Teeth          => { Bite => 0.3, ToxicBite => 0.2, Blunt => 0.17, Scratch => 0.077 }, # Gigantopithecus (Megasloth 0.282)
    Mouth          => { Bite => 0.2, ToxicBite => 0.2, Scratch => 0.077 }, # Arthropleura, Cobra(T)
    TuskAttackTool => { Cut => 0.261, Stab => 0.489, Scratch => 0.077 },   # Elephant
    Feet           => { Blunt => 0.17, Slash => 0.2, Scratch => 0.077 },   # Titanis(Sl)

    LeftLeg        => { Blunt => 0.17, Scratch => 0.077 },
    RightLeg       => { Blunt => 0.17, Scratch => 0.077 },
    FrontLeftLeg   => { Blunt => 0.17, Scratch => 0.077 },   # Elephant

    LeftHand       => { Blunt => 0.17, Slash => 0.3, Scratch => 0.077 },    # Gigantopithecus(S)
    FrontLeftPaw   => { Slash => 0.25, Scratch => 0.077 },   # Doedicurus (Megasloth 0.282)
    FrontLeftClaws  => { Slash => 0.227, Scratch => 0.077 },  # Megascarab, Lynx
    LeftBlade      => { Cut => 0.207, Stab => 0.388, Blunt => 0.133, Scratch => 0.077 },  # Scyther(C/S)
);
# (Megafauna sets a lot of AP to 0.3 in a17, including Blunt. Don't use that for reference.)

# Similar
$TOOLAP{Beak} = $TOOLAP{Teeth};

$TOOLAP{RightLeg} = $TOOLAP{LeftLeg};
$TOOLAP{FrontRightLeg} = $TOOLAP{FrontLeftLeg};
$TOOLAP{RightHand} = $TOOLAP{LeftHand};
$TOOLAP{FrontRightPaw} = $TOOLAP{FrontLeftPaw};

$TOOLAP{LeftArmClawAttackTool} = $TOOLAP{FrontLeftClaws};
$TOOLAP{LeftLegClawAttackTool} = $TOOLAP{FrontLeftClaws};

$TOOLAP{RightLegClawAttackTool} = $TOOLAP{LeftLegClawAttackTool};
$TOOLAP{RightArmClawAttackTool} = $TOOLAP{LeftArmClawAttackTool};
$TOOLAP{FrontRightClaws} = $TOOLAP{FrontLeftClaws};
$TOOLAP{RightBlade} = $TOOLAP{LeftBlade};

# Megafauna typos
$TOOLAP{TailWeapon} = $TOOLAP{TailAttackTool};
$TOOLAP{FeetGroup}  = $TOOLAP{Feet};

# Converting old verbs nodes to tools node (b18)
# Translate old field names.
# - If value is $SKIPVERBFIELD, don't include in new tools node.
# - If not listed here, translate field verbatim.
my $SKIPVERBFIELD = "__SKIP";
my %VERB2TOOL = (
       verbClass             => $SKIPVERBFIELD, # a17: used to have value "CombatExtended.Verb_MeleeAttackCE"
       defaultCooldownTime   => "cooldownTime",
       meleeDamageBaseAmount => "power",
       meleeDamageDef        => "capacities",  # will translate to capacities list
       #linkedBodyPartsGroup => "linkedBodyPartsGroup",
       #commonality          => "commonality",
);

# Constructor
#
# Params:
# - sourcemod   - (string) If given, patch won't apply unless this mod is loaded
# - sourcefile  - (string) $source_file_path
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

    # Init and Header
    $self->__start_patch();

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
        $val = $self->{cedata}->{$patchable}->{bodyShape} || $DEFAULT{bodyShape};
        $self->__print_patch(<<EOF);
    <li Class="PatchOperationAddModExtension">
    <xpath>Defs/ThingDef[defName="$patchable"]</xpath>
    <value>
        <li Class="CombatExtended.RacePropertiesExtensionCE">
            <bodyShape>$val</bodyShape>
        </li>
    </value>
    </li>

EOF

	# Element defines "verbs" (pre-b18).
	# Convert these to "tools" nodes and remove the old verbs nodes (else CE errors).
        if ($elem->{verbs}->{li})
	{
	    $self->__print_patch(<<EOF);
    <!-- Patch $patchable : Verbs (convert to tools) -->

    <!-- Add tools node if it doesn't exist -->
    <li Class="PatchOperationSequence">
    <success>Always</success>
    <operations>
        <li Class="PatchOperationTest">
        <xpath>/Defs/ThingDef[defName="$patchable"]/tools</xpath>
            <success>Invert</success>
        </li>
        <li Class="PatchOperationAdd">
        <xpath>/Defs/ThingDef[defName="$patchable"]</xpath>
            <value>
                <tools />
            </value>
        </li>
    </operations>
    </li>

    <!-- Convert old verbs to new tools nodes -->
    <li Class="PatchOperationAdd">
    <xpath>Defs/ThingDef[defName="$patchable"]/tools</xpath>
    <value>
EOF
	    # Step through verb fields in source xml
            foreach $verb ( @{ $elem->{verbs}->{li} } )
            {
	        $self->__print_patch(<<EOF);
        <li Class="CombatExtended.ToolCE">
EOF

		# Add <label> and <id>.
		if (exists $verb->{linkedBodyPartsGroup})
		{
		    $val = $self->__get_tool_label($verb->{linkedBodyPartsGroup});
	            $self->__print_patch(<<EOF);
            <label>$val</label>
EOF
		    if (exists $verb->{meleeDamageDef})
		    {
		        $val = $self->__get_tool_id($verb->{linkedBodyPartsGroup}, $verb->{meleeDamageDef});
	                $self->__print_patch(<<EOF);
            <id>$val</id>
EOF
		    }
		}

		# Add verbClass (else CE warning)
	        $self->__print_patch(<<EOF);
            <verbClass>CombatExtended.Verb_MeleeAttackCE</verbClass>
EOF

		# Add remaining fields
		foreach $key ( sort keys %$verb )  # print sorted to avoid unnecessary diffs
		{
		    # Translate/Copy field names
	            if (exists $VERB2TOOL{$key})
		    {
			next if $VERB2TOOL{$key} eq $SKIPVERBFIELD;
			$tag = $VERB2TOOL{$key};
		    }
		    else
		    {
			$tag = $key
		    }

		    # Capacities - add as list
		    $val = $tag eq "capacities" ? "<li>$verb->{$key}</li>" : $verb->{$key};

		    # Add to new tools node
                    $self->__print_patch(<<EOF);
            <$tag>$val</$tag>
EOF
		}

                # Add CE armor penetration
		$val = $self->__get_tool_armor_pen($verb->{linkedBodyPartsGroup}, $verb->{meleeDamageDef}, $patchable);
	        $self->__print_patch(<<EOF);
            <armorPenetration>$val</armorPenetration>
        </li>
EOF
	    }

	    # Close new tools node + Delete old verbs node
	    $self->__print_patch(<<EOF);
    </value>
    </li>

    <!-- Delete old verbs node (causes CE errors) -->
    <li Class="PatchOperationRemove">
    <xpath>Defs/ThingDef[defName="$patchable"]/verbs</xpath>
    </li>

EOF
	}

	# Element defines "tools".
        # For each bodypartgroup listed for this entity, add CE attribute + armor pen value
	#
	# (mod shouldn't define both verbs and tools, but we won't assume that)
	#
        if ($elem->{tools}->{li})
        {
	    $self->__print_patch(<<EOF);
    <!-- Patch $patchable : Tools -->

EOF
            foreach $tool ( @{ $elem->{tools}->{li} } )
            {
		# armor penetration
		$val = $self->__get_tool_armor_pen($tool->{linkedBodyPartsGroup}, $tool->{capacities}->{li}->[0], $patchable);

		# Patch tool by id || bodypartgroup
		# (id needed if multiple capacities for same body, else not defined,
		#  e.g. hornscratch, horn)
		#
	        $tag = $tool->{id} ? "id" : "linkedBodyPartsGroup";
                $self->__print_patch(<<EOF);
    <li Class="PatchOperationAttributeSet">
    <xpath>Defs/ThingDef[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]</xpath>
        <attribute>Class</attribute>
        <value>CombatExtended.ToolCE</value>
    </li>

    <li Class="PatchOperationAdd">
    <xpath>Defs/ThingDef[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]</xpath>
    <value>
        <armorPenetration>$val</armorPenetration>
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
        $val = <<EOF;
    <!-- Patch statBases last so that we know all previous sequence entries succeeded.
         These values are easy to check in-game. -->
    <li Class="PatchOperationAdd">
    <xpath>Defs/ThingDef[defName="$patchable"]/statBases</xpath>
    <value>
        <MeleeDodgeChance>$self->{cedata}->{$patchable}->{MeleeDodgeChance}</MeleeDodgeChance>
        <MeleeCritChance>$self->{cedata}->{$patchable}->{MeleeCritChance}</MeleeCritChance>
EOF

        # statBases: armor values (if undefined, fallback to core)
        foreach $tag (@ARMORTYPES)
        {
            if (exists $self->{cedata}->{$patchable}->{$tag})
	    {
	        $val = $val . <<EOF;
        <$tag>$self->{cedata}->{$patchable}->{$tag}</$tag>
EOF
	    }
        }

        # Add all (defined) statBases
        $self->__print_patch(<<EOF);
$val
    </value>
    </li>

EOF

    }

    # Closer
    $self->__end_patch();

    return 1; # success
}


#############
# Utilities #
#############

# Pre-patch initialization and header
sub __start_patch
{
    my($self) = @_;

    $self->__setup_patch_dir();
    $self->__info("Source - $self->{sourcefile}");
    $self->__info("Patch  - " . $self->__init_patchfile($self->{sourcefile}) . "\n");
    $self->__init_sourcexml($self->{sourcefile});

    $self->__print_patch_header();

    $self->__print_sourcemod_check();
}

# Determine armor penetration value for this tools node
sub __get_tool_armor_pen
{
    my($self, $bodypartgroup, $capacity, $name) = @_;

    # Warn if need to update %TOOLAP
    my $ap = eval { $TOOLAP{$bodypartgroup}->{$capacity} };  # ?.
    if (!defined $ap)
    {
        $self->__warn("$patchable: $name: Unknown tool $bodypartgroup capacity $capacity. Using default AP. Please update \%TOOLAP.");
        $ap = $DEFAULT_AP;
    }

    return $ap;
}

# Generate the label/id for a tools/verbs node using bodypart+capacity
sub __get_tool_label
{
    my($self, $bodypart) = @_;

    my $label = $bodypart;
    $label =~ s/(\S)([A-Z])/$1 $2/g;  # "HeadAttackTool" = > "Head Attack Tool"
    $label = lc($label);
    $label =~ s/ ?attack tool//;      # => "head"
    return $label;
}
sub __get_tool_id
{
    my($self, $bodypart, $capacity) = @_;
    return lc($bodypart . $capacity);
}

1;

__END__

