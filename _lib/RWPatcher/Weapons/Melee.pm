package RWPatcher::Weapons::Melee;

# Generate patch files for melee weapon mod files (e.g. Star Wars Lightsabers).

use XML::Simple;
use File::Basename qw(dirname basename);

#
# Generate CE patch for sourcefile(s):
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
# Params:
# - sourcemod   - (string) If given, patch won't apply unless this mod is loaded
# - sourcefiles - \@source_file_paths
# - cedata      - Combat Extended data for each animal to be patched,
#                 { [ anim1 => \%data ], ... }
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
    my $self = {};
    my $errcount = 0;  # count all validation errors before dying

    bless($self, $class);

    # Verify - \@sourcefiles
    if (!$params{sourcefiles} || ref($params{sourcefiles}) ne 'ARRAY')
    {
        ____warn("new(): sourcefiles parameter is not an array");
	++$errcount;
    }

    # Verify - \%cedata
    if (!$params{cedata} || ref($params{cedata}) ne 'HASH')
    {
        ____warn("new(): cedata parameter is not a hash");
	++$errcount;
    }

    my($weapon, $data, $required);
    while ( ($weapon,$data) = each %{$params{cedata}} )
    {
        foreach $required ( qw(Bulk) )
	{
	    if (!$data->{$required})
	    {
	        ____warn("new(): cedata entry for $weapon is missing required parameter: $required");
		++$errcount;
	    }
	}

	# don't bother validating optional params
    }

    # Exception if invalid
    if ($errcount > 0)
    {
        ____die("new(): Found $errcount validation errors.");
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
	    mkdir($outdir) or ____die("mkdir $outdir: $!");
	}
	elsif (! -d $outdir)
	{
	    ____die("Output dir $outdir exists but is not a directory.");
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

    <!-- Warning: This will break if original mod moves weapons into diff files.
         Use a patch sequence for each file to reduce load times. -->

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

    # Step through source xml.
    # Generate patch for each known defName/blaster in the same order.
    my($weapon, $data, $key, $val, $ref);
    foreach my $entry ( @{$source->{ThingDef}} )
    {
        next unless exists($entry->{defName}) && exists $self->{cedata}->{$entry->{defName}};
        $weapon = $entry->{defName};
        $data = $self->{cedata}->{$entry->{defName}};
    
        # Add CE bulk
        __print_patch(<<EOF);

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
            __print_patch(<<EOF);
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
                __print_patch(<<EOF);
                <li>$key</li>
EOF
	    }

            __print_patch(<<EOF);
	    </value>
	</li>

EOF
        }

        # Add CE attribute to tools node entries
        __print_patch(<<EOF);
	<!-- Add CE attribute to all tools entries -->
	<li Class="PatchOperationAttributeSet">
	    <xpath>Defs/ThingDef[defName="$weapon"]/tools/li</xpath>
	    <attribute>Class</attribute>
	    <value>CombatExtended.ToolCE</value>
	</li>

EOF
        # Add armor penetration to all tools entries
        if (exists $entry->{tools} && exists $entry->{tools}->{li})
        {
	    foreach $ref ( @{$entry->{tools}->{li}} )
	    {
                # AP based on capacity (default to a17 value || 0.01)
	        $key = $ref->{capacities}->{li}->[0];
	        $val = $key && $AP{$key} ? $AP{$key} : ($data->{armorPenetration} || 0);
                __print_patch(<<EOF);
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
	    __print_patch(<<EOF);
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

    # Add armor penetration to all tools node entries

    # Closer
    __print_patch(<<EOF);
  </operations>  <!-- end sequence -->
  </Operation>   <!-- end sequence -->

</Patch>

EOF
    close(OUTFILE) or __warn("close $outfile: $!\n");

    } # end foreach sourcefile

    return 1;  # success
} # end generate_patches()

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

