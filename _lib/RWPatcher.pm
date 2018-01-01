package RWPatcher;

# Base for RWPatcher classes

use XML::Simple;
use File::Basename qw(dirname basename);
use IO::File;

# Constructor
# Validate parameters
#
# Parameters:
# - params    => \%params - child parameters
# - validator => \%validator - validate params against this. See below example.
#
# $validator example = {
#     $paramname1 => {required => 1, type => ""},      # string/int/etc.
#     $paramname2 => {required => 0, type => "ARRAY"},
#     $paramname3 => {required => 0, type => "HASH"},
# }
#
# Expected child parameters:
# - sourcefile  - (string) $source_file_paths
# - cedata      - (hashref) Combat Extended data for each entity to be patched,
#                 { [ entity1 => \%data ], ... }
#
# Optional child parameters:
# - sourcemod  => (string) Don't apply patch unless this mod is loaded.
# - patchdir   => (string) write patches to this dir (default: auto-use name of immediate parent dir of sourcefile)
# - base_node_name => (string) Name of base node to parse (default "ThingDef")
# - expected_parents => (string/array-ref)
#                If given, patch only ThingDefs with this ParentName.
#                If multiple(array-ref), element must match one of the listed ParentName(s).
#                If not given, patch only defs with defName in cedata.
#                Specifying parent_thing will identify new entries in source xml that
#                are not defined in cedata.
#
# The format of cedata depends on the child and is validated against \%validator.
#
sub new
{
    my($class, %params) = @_;
    my $errcount = 0;  # count all validation errors before dying

    my $self = {};
    bless($self, $class);

    my $params = $params{params} or $self->__die("new(): Missing parameter: params");
    my $validator = $params{validator} or $self->__die("new(): Missing parameter: validator");

    # Verify - \@sourcefile
    if (!$params->{sourcefile} || ref($params->{sourcefile}) ne '')
    {
        $self->__warn("new: sourcefile parameter is missing or is not a string (got ".ref($params->{sourcefile}).")");
	++$errcount;
    }

    # Verify - \%cedata
    if (!$params->{cedata} || ref($params->{cedata}) ne 'HASH')
    {
        $self->__warn("new: cedata parameter is missing or is not a hash (got ".ref($params->{cedata}).")");
	++$errcount;
    }

    # Verify - optional strings
    my $param;
    foreach $param (qw(sourcemod patchdir base_node_name))
    {
        if (defined $params->{$param} && ref($params->{$param}) ne '')
        {
            $self->__warn("new: $param parameter is not a string (got ".ref($params->{$param}).")");
    	    ++$errcount;
        }
    }

    # Verify - $expected_parents || \@expected_parents
    if (defined $params->{expected_parents} && !ref($params->{expected_parents}) eq '' && !ref($params->{expected_parents}) eq 'ARRAY')
    {
        $self->__warn("new: expected_parents parameter is not a string or array-ref (got ".ref($params->{expected_parents}).")");
        ++$errcount;
    }

    # For each cedata entry, check for required parameters and validate parameter types
    # Any unexpected keys in cedata are ignored, no warning.
    my($entity, $data, $valid);
    while ( ($entity,$data) = each %{$params->{cedata}} )
    {
        while ( ($param, $valid) = each %$validator )
        {
            if ($valid->{required} && !exists $data->{$param})
            {
                $self->__warn("new: cedata for $entity is missing required parameter: $param");
                ++$errcount;
            }
            elsif (ref($data->{$param}) ne $valid->{type})
            {
                $self->__warn("new: cedata for $entity param $param has bad type ", ref($data->{$param}), " (expected $valid->{type}).");
                ++$errcount;
            }
        }
    }

    # If any fields are required, then we will require a cedata entry for all patches
    #$self->{__validator} = $validator;
    $self->{__patches_require_cedata} = 0;
    while ( !$self->{__patches_require_cedata} && ((undef, $valid) = each %$validator) )
    {
        $self->{__patches_require_cedata} = 1 if $valid->{required};
    }

    # Exception if invalid
    if ($errcount > 0)
    {
        $self->__die("new: Found $errcount validation errors.");
    }

    # Valid - Init
    $self->{sourcefile} = $params->{sourcefile};
    $self->{cedata}     = $params->{cedata};
    $self->{sourcemod}  = $params->{sourcemod} if defined $params->{sourcemod};
    $self->{patchdir}   = $params->{patchdir}  if defined $params->{patchdir};
    $self->base_node_name($params->{base_node_name}) if $params->{base_node_name};
    $self->expected_parents($params->{expected_parents}) if $params->{expected_parents};
    return $self;
}

#########################
# Patch target criteria #
#########################

# Patch this child element if one of the following is true:
#   1. expected_parents is set and this child's ParentName matches it.
#   2. child's defName is defined in this object's cedata.
#
# To change selection criteria, overwrite is_elem_patchable() or expected_parents().
#
# Return:
#   - 1 - yes, patchable
#   - 0 - don't patch
#
# Side effects:
#   - Warn if we found a child definition matching expected_parents that is not
#     defined in cedata.  This helps locate new definitions in source mod that need cedata.
#
sub is_elem_patchable
{
    my($self, $thiselem) = @_;

    my $defname = $thiselem->{defName};

    return 0 unless defined $defname;
    
    if ($self->has_expected_parents())
    {
        if ($self->is_expected_parent($thiselem->{ParentName}))
	{
	    # Warn user to update cedata for new patchable elements found in source mod
	    if (!defined $self->{cedata}->{$defname} && $self->{__patches_require_cedata})
	    {
	        $self->__warn("New entity found: $defname (Skipping - Please add CE DATA).");
	        return 0;
	    }
	    return 1;
	}

	# If defined in cedata, patch it even though parent doesn't match, but warn user.
        elsif (defined $self->{cedata}->{$defname})
	{
            $self->__warn("Entity '$defname' in cedata has unexpected parent '$thiselem->{ParentName}'. Patching anyway.");
	    return 1;
	}
	return 0;
    }

    # If caller didn't define expected parent, only patch elements defined in his cedata.
    if (defined $self->{cedata}->{$defname})
    {
        return 1;
    }

    # Don't patch
    return 0;
}

# Get/Set name of base node to parse (ThingDef, PawnKindDef, etc.)
sub base_node_name
{
    my($self, $name) = @_;
    $self->{base_node_name} = $name if defined $name;
    return $self->{base_node_name} || "ThingDef";
}

# XML element matches one of the expected ParentName's (and should be patched)
#
# For more complex criteria, overwrite is_elem_patchable().
#
sub is_expected_parent
{
    my($self, $parentname) = @_;
    $parentname = "" unless defined $parentname;
    return exists $self->expected_parents()->{$parentname} ? 1 : 0;
}

# This object checks vs parents (else only checks vs cedata)
sub has_expected_parents
{
    my($self) = @_;
    return defined $self->expected_parents() ? 1 : 0;
}

# Set expected parent class(es) of xml defs to be patched.
# Accepts array/array-ref, Returns hash-ref.
sub expected_parents
{
    my($self, @parentnames) = @_;

    if (@parentnames)
    {
        $self->{expected_parents} = { map { $_ => 1 } (ref($parentnames[0]) eq 'ARRAY' ? @{$parentnames[0]} : @parentnames) };
    }
    return $self->{expected_parents};
}

#############
# Utilities #
#############

# Print to patch file
sub __print_patch
{
    my($self, @msg) = @_;
    if ($self->{patchfh})
    {
        $self->{patchfh}->print(@msg);
    }
    else
    {
        print(@msg);
    }
}

####################
# Patch Init/Setup #
####################

# Pre-patch initialization and header
sub __start_patch
{
    my($self) = @_;

    $self->__info("Source - $self->{sourcefile}");
    $self->__info("Patch  - " . $self->__init_patchfile() . "\n");
    $self->__init_sourcexml($self->{sourcefile});

    $self->__print_patch_header();

    $self->__print_sourcemod_check();

    return 1;
}

# Given a file name, init the xml object to parse
sub __init_sourcexml
{
    my($self, $filename) = @_;
    $self->{sourcexml} =  XMLin($filename, ForceArray => [$self->base_node_name(), "li"])
        or $self->__die("read source xml $filename: $!\n");
    return $self->{sourcexml};
}

# Given a sourcefile name, init the target patch file
# Store patch filename / filehandle in $self->{patchfile} / $self->{patchfh}.
# Return patch filename.
#
# Translate sourcefilename => patchfilename:
# - Use same parent dir name, but in current dir ("./same-subdir/patchfile.xml")
# - Source files may end in ".xml" or ".txt" or "-REF.txt" (all translated to ".xml").
#
sub __init_patchfile
{
    my($self) = @_;

    my $sourcefile = $self->{sourcefile};
    $sourcefile =~ s/(?:-REF)?\.txt/.xml/;

    my $patchdir = $self->{patchdir} || basename(dirname($sourcefile));
    $self->__setup_patch_dir($patchdir);

    $self->{patchfile} = $patchdir . "/" . basename($sourcefile);
    #open($self->{patchfh}, ">", $self->{patchfile})
    $self->{patchfh} = new IO::File(">" . $self->{patchfile})
        or $self->__die("Failed to open/write $self->{patchfile}: $!\n");

    return $self->{patchfile};
}

# Given a source mod file to be patched, setup the target patch directory.
#
# Ex: Source = ../../SourceModName/ThingDefs_Races/File.xml
#     Patch  = ./ThingDefsRaces/File.xml
# So we need to create the ThingDefRaces dir if it doesn't exist.
#
sub __setup_patch_dir
{
    my($self, $patchdir) = @_;

    if (! -e $patchdir)
    {
        mkdir($patchdir) or $self->__die("mkdir $patchdir: $!");
    }
    elsif (! -d $patchdir)
    {
        $self->__die("Output dir $patchdir exists but is not a directory.");
    }
    # If file is in current dir ".", then $patchdir = ".." above and passes without error

    return 1; # success
}

#########################
# Common patch contents #
#########################
sub __print_patch_header
{
    my($self) = @_;

    $self->__print_patch(<<EOF);
<?xml version="1.0" encoding="utf-8" ?>
<Patch>

    <!-- Warning: This patch will break if original mod moves weapons into diff files.
         To fix this, please re-run script using new mod file paths. -->

  <Operation Class="PatchOperationSequence">
  <success>Always</success>
  <operations>

EOF
}

sub __print_sourcemod_check
{
    my($self) = @_;

    if (exists $self->{sourcemod})
    {
        $self->__print_patch(<<EOF);
    <li Class="CombatExtended.PatchOperationFindMod">
        <modName>$self->{sourcemod}</modName>
    </li>

EOF
    }
}

sub __print_element_header
{
    my($self, $header) = @_;

        # Start patch
        $self->__print_patch(<<EOF);
    <!-- ========== $header ========== -->

EOF
}

################
# Patch Finish #
################
sub __end_patch
{
    my($self) = @_;

    $self->__print_patch_closer();
    $self->__close_patchfile();
}

sub __print_patch_closer
{
    my($self) = @_;

    $self->__print_patch(<<EOF);
  </operations>  <!-- end sequence -->
  </Operation>   <!-- end sequence -->

</Patch>

EOF
}

sub __close_patchfile
{
    my($self) = @_;
    $self->{patchfh} && $self->{patchfh}->close() || $self->__warn("close $self->{patchfile}: $!");
}

# Messages
sub __info { shift; print(@_, "\n"); }
sub __warn { my($self, @msg) = @_; warn((ref($self) || $self), "> WARN: ", @msg, "\n"); }
sub __die  { my($self, @msg) = @_; warn((ref($self) || $self), "> ERR: ", @msg, "\n"); exit(1); }

1;

__END__

