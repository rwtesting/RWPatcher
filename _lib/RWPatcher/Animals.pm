package RWPatcher::Animals;

# Generate patch files for animal mod file(s) (e.g. Dinosauria).

use XML::Simple;
use File::Basename qw(basename dirname);

#
# Generate patch to make Dinosauria races compatible with Combat Extended, b18.
#

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
    my $self = {};
    my $errcount = 0;  # count all validation errors before dying

    bless($self, $class);

    # Verify - \@sourcefiles
    if (!$params{sourcefiles} || ref($params{sourcefiles}) ne 'ARRAY')
    {
        __warn("new(): sourcefiles parameter is not an array");
	++$errcount;
    }

    # Verify - \%cedata
    if (!$params{cedata} || ref($params{cedata}) ne 'HASH')
    {
        __warn("new(): cedata parameter is not a hash");
	++$errcount;
    }

    my($animal, $data, $required);
    while ( ($animal,$data) = each %{$params{cedata}} )
    {
        foreach $required ( qw(MeleeDodgeChance MeleeCritChance) )
	{
	    if (!$data->{$required})
	    {
	        __warn("new(): cedata entry for $animal is missing required parameter: $required");
		++$errcount;
	    }
	}

	# don't bother validating optional params
    }

    # Exception if invalid
    if ($errcount > 0)
    {
        __die("new(): Found $errcount validation errors.");
    }

    # Valid - init
    $self->{sourcefiles} = $params{sourcefiles};
    $self->{cedata}      = $params{cedata};
    $self->{sourcemod}   = $params{sourcemod} if exists $params{sourcemod};
    return $self;
}

# Generate patch files for this patcher
sub generate_patches
{
    my($self) = @_;

    # Make sure output dirs are created before trying to write any patches
    my($sourcefile, $outdir);
    foreach $sourcefile (@{$self->{sourcefiles}})
    {
        $outdir = basename(dirname($sourcefile));
	if (! -e $outdir)
	{
	    mkdir($outdir) or __die("mkdir $outdir: $!");
	}
	elsif (! -d $outdir)
	{
	    __die("Output dir $outdir exists but is not a directory.");
	}
    }

    # Patch each source file
    my($source, $outfile);
    foreach $sourcefile (@{$self->{sourcefiles}})
    {

    __info("Source - $sourcefile");

    # Generate output patch file name
    $sourcefile =~ s/(?:-REF)?\.txt/.xml/;
    $outfile = basename(dirname($sourcefile)) . "/" . basename($sourcefile);
    __info("Patch  - $outfile\n");

    # Open source/output files
    $source =  XMLin($sourcefile, ForceArray => [qw(ThingDef li)])
        or __die("read source xml $sourcefile: $!\n");
    open(OUTFILE, ">", $outfile)
        or __die("Failed to open/write $outfile: $!\n");

    # Header 
    __print_patch(<<EOF);
<?xml version="1.0" encoding="utf-8" ?>
<Patch>

  <Operation Class="PatchOperationSequence">
  <success>Always</success>
  <operations>

EOF

    # Is source mod loaded?
    if (exists $self->{sourcemod})
    {
        __print_patch(<<EOF);
    <li Class="CombatExtended.PatchOperationFindMod">
        <modName>$self->{sourcemod}</modName>
    </li>

EOF
    }

    #
    # Step through source xml.
    # Generate a template for each $patchable found.
    # If entity is found that we don't have CE values for, warn and skip.
    #
    # Perf:
    # - Use one sequence per file to reduce load times, short circuit.
    # - Load times: Defs/ThingDef < /Defs/ThingDef << */ThingDef/ <<< //ThingDef/
    #
    my($patchable, $tool, $ap, $bodyshape, $armortype, $statbases, $tag);
    foreach my $entry ( @{$source->{ThingDef}} )
    {
        # Skip non-entities and unknown entities
        next unless ($patchable = $entry->{defName}) && $entry->{ParentName} eq "AnimalThingBase";

        if (!exists $self->{cedata}->{$patchable})
        {
            __warn(<<EOF);
WARN: New or unknown entity found. Skipping because no CE data:

Name: $patchable
Desc:
$entry->{description}

EOF
            next;
        }

        # Start patch
        __print_patch(<<EOF);
    <!-- ========== $patchable ========== -->

EOF

        # Add bodyShape
        $bodyshape = $self->{cedata}->{$patchable}->{bodyShape} || $DEFAULT{bodyShape};
        __print_patch(<<EOF);
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
        if ($entry->{tools}->{li})
        {
	    __print_patch(<<EOF);
    <!-- Patch $patchable : Tools / Verbs -->

EOF
            foreach $tool ( @{ $entry->{tools}->{li} } )
            {
                $ap = $DEFAULT_AP{$tool->{linkedBodyPartsGroup}} || $DEFAULT_AP;
	        $tag = $tool->{id} ? "id" : "linkedBodyPartsGroup"; # rare case where 2 entries for same bodypart, different id (e.g. Megafauns hornScratch/hornBlunt are both HornAttackTool).
                __print_patch(<<EOF);
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
                    __print_patch(<<EOF);
    <!-- HACK: temporarily remove stun nodes to prevent CE v0.18.0.2 beta null object error -->
    <li Class="PatchOperationRemove">
    <xpath>Defs/ThingDef[defName="$patchable"]/tools/li[$tag="$tool->{$tag}"]/surpriseAttack</xpath>
    </li>

EOF
	        }
            }
        }

        # Adjust stats
        __print_patch(<<EOF);
    <!-- Patch $patchable : Stats -->

EOF

        # Add baseHealthScale
        if (exists $self->{cedata}->{$patchable}->{baseHealthScale})
        {
            __print_patch(<<EOF);

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
        __print_patch(<<EOF);
$statbases
    </value>
    </li>

EOF

    }

    # print closer
    __print_patch(<<EOF);
  </operations> <!-- End sequence -->
  </Operation>  <!-- End sequence -->

</Patch>

EOF

    close(OUTFILE) or __warn("WARN: close $outfile: $!\n");

    }  # end foreach source file

    return 1; # success
}  # end generate_patches()

#############
# FUNCTIONS #
#############

# print to patch file (uses global filehandle OUTFILE)
sub __print_patch {
    print OUTFILE (@_);
}

# Util
sub __info { print(__PACKAGE__, ": ", @_, "\n"); }
sub __warn { warn(__PACKAGE__, ": WaRN: ", @_, "\n"); }
sub __die  { warn(__PACKAGE__, ": ERR: ", @_, "\n"); exit(1); }

__END__

