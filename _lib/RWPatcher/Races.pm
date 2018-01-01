package RWPatcher::Races;

# Generate patch files for animal mod file(s) (e.g. Dinosauria).

use RWPatcher;
use parent "RWPatcher";

# Source file name format:
# For each, patch file will be ./<base-dir-name>/<file.xml>
# Source may end with (-REF)?.(txt|xml), which will be replaced with ".xml".

###########################
# CLASS CONSTANTS (no my) #
###########################

# DEFAULT values not in source xml
%DEFAULT = (
    bodyShape => "Humanoid",
    #MeleeDodgeChance => 0.08,	# Elephant
    #MeleeCritChance  => 0.79,	# Elephant
);

# Armor types to check (if not defined, don't patch - fallback to source mod values).
@ARMORTYPES = qw(ArmorRating_Blunt ArmorRating_Sharp);

# Armor penetration per bodypart
#
# TODO: Simplify this by approximating all AP by capacity, ignore bodypartgroup,
#       and allow caller/child to specify exceptions per entity+bodypart+capacity.
#
$DEFAULT_AP = 0.15;  # default ap for unlisted bodyparts/capacities
%TOOLAP = (
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

$TOOLAP{LeftHandClawsGroup} = $TOOLAP{FrontLeftClaws};
$TOOLAP{RightHandClawsGroup} = $TOOLAP{LeftHandClawsGroup};

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

# Constructor - use parent

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
    # - Load times: Defs/ThingDef < Defs/ThingDef << */ThingDef/ <<< //ThingDef/
    #
    my $basenode = $self->base_node_name();
    foreach $elem ( @{$self->{sourcexml}->{$basenode}} )
    {
        # Skip non-entities and unknown entities
        next unless $self->is_elem_patchable($elem);
	$patchable = $elem->{defName};
	$self->__print_element_header($patchable);

        # Add bodyShape
        $val = $self->{cedata}->{$patchable}->{bodyShape} || $DEFAULT{bodyShape};
        $self->__print_patch(<<EOF);
    <li Class="PatchOperationAddModExtension">
    <xpath>Defs/${basenode}[defName="$patchable"]</xpath>
    <value>
        <li Class="CombatExtended.RacePropertiesExtensionCE">
            <bodyShape>$val</bodyShape>
        </li>
    </value>
    </li>

EOF

	# Insert from child
	$self->__generate_patches_first($elem);

	# Element defines "verbs" (pre-b18).
	# Convert these to "tools" nodes and remove the old verbs nodes (else CE errors).
        if (ref(eval{$elem->{verbs}->{li}}) eq 'ARRAY')
	{
	    $self->__print_patch(<<EOF);
    <!-- Patch $patchable : Verbs (convert to tools) -->

    <!-- Add tools node if it doesn't exist -->
    <li Class="PatchOperationSequence">
    <success>Always</success>
    <operations>
        <li Class="PatchOperationTest">
        <xpath>Defs/${basenode}[defName="$patchable"]/tools</xpath>
            <success>Invert</success>
        </li>
        <li Class="PatchOperationAdd">
        <xpath>Defs/${basenode}[defName="$patchable"]</xpath>
            <value>
                <tools />
            </value>
        </li>
    </operations>
    </li>

    <!-- Convert old verbs to new tools nodes -->
    <li Class="PatchOperationAdd">
    <xpath>Defs/${basenode}[defName="$patchable"]/tools</xpath>
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
    <xpath>Defs/${basenode}[defName="$patchable"]/verbs</xpath>
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
    <xpath>Defs/${basenode}[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]</xpath>
        <attribute>Class</attribute>
        <value>CombatExtended.ToolCE</value>
    </li>

    <li Class="PatchOperationAdd">
    <xpath>Defs/${basenode}[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]</xpath>
    <value>
        <armorPenetration>$val</armorPenetration>
    </value>
    </li>

EOF

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
    <xpath>Defs/${basenode}[defName="$patchable"]/race/baseHealthScale</xpath>
    <value>
        <baseHealthScale>$self->{cedata}->{$patchable}->{baseHealthScale}</baseHealthScale>
    </value>
    </li>

EOF
        }


        # statBases: dodge, crit, armor values (if undefined, fallback to core)
	$val = "";
        foreach $tag (qw(MeleeDodgeChance MeleeCritChance), @ARMORTYPES)
        {
            if (exists $self->{cedata}->{$patchable}->{$tag})
	    {
	        $val = $val . <<EOF;
        <$tag>$self->{cedata}->{$patchable}->{$tag}</$tag>
EOF
	    }
        }

        # Add all (defined) statBases
	if ($val =~ /\S/)
	{
            $self->__print_patch(<<EOF);
    <!-- Patch statBases last so that we know all previous sequence entries succeeded.
         These values are easy to check in-game. -->

    <li Class="PatchOperationAdd">
    <xpath>Defs/${basenode}[defName="$patchable"]/statBases</xpath>
    <value>
$val
    </value>
    </li>

EOF
	}

	# Insert from child
	$self->__generate_patches_last($elem);
    }

    # Closer
    $self->__end_patch();

    return 1; # success
}

sub __generate_patches_first
{
   my($self, $curelem) = @_;  # $curelem is the $elem from the source xml that we're processing
   ## Let child insert patches first in sequence
}

sub __generate_patches_last
{
   my($self, $curelem) = @_;  # $curelem is the $elem from the source xml that we're processing
   ## Let child insert patches last in sequence
}


#############
# Utilities #
#############

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

