package RWPatcher;

# Base for RWPatcher classes

use XML::Simple;
use File::Basename qw(dirname basename);
use IO::File;
#use Data::Dumper qw(Dumper);

# Constructor
# Validate parameters
#
# Parameters:
# - params    => \%params - child parameters
# - validator => \%validator - validate params against this. See below example.
#
# $validator example = {
#     $paramname1 => {required => 1, type => ""},      # scalar (string/int/etc.)
#     $paramname2 => {required => 0, type => "ARRAY"},
#     $paramname3 => {required => 0, type => "HASH"},
# }
#
# Expected child parameters:
# - sourcefiles - \@source_file_paths
# - cedata      - Combat Extended data for each entity to be patched,
#                 { [ entity1 => \%data ], ... }
# - sourcemod   - (optional/string) If given, patch won't apply unless this mod is loaded
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

    # Verify - \@sourcefiles
    if (!$params->{sourcefiles} || ref($params->{sourcefiles}) ne 'ARRAY')
    {
        $self->__warn("new: sourcefiles parameter is missing or is not an array");
	++$errcount;
    }

    # Verify - \%cedata
    if (!$params->{cedata} || ref($params->{cedata}) ne 'HASH')
    {
        $self->__warn("new: cedata parameter is missing or is not a hash");
	++$errcount;
    }

    # For each cedata entry, check for required parameters and validate parameter types
    # Any unexpected keys in cedata are ignored, no warning.
    my($entity, $data, $param, $valid);
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

    # Exception if invalid
    if ($errcount > 0)
    {
        $self->__die("new: Found $errcount validation errors.");
    }

    # Valid - Init
    $self->{sourcefiles} = $params->{sourcefiles};
    $self->{cedata}      = $params->{cedata};
    $self->{sourcemod}   = $params->{sourcemod} if exists $params->{sourcemod};
    return $self;
}

# Given a set of source mod files to be patched, setup the target patch directories.
# Do this for all source files at once before patching anything.
#
# Ex: Source = ../../SourceModName/ThingDefs_Races/File.xml
#     Patch  = ./ThingDefsRaces/File.xml
# So we need to create the ThingDefRaces dir if it doesn't exist.
#
sub __setup_patch_dirs
{
    my($self) = @_;

    my($sourcefile, $outdir);
    foreach $sourcefile (@{$self->{sourcefiles}})
    {
        $outdir = basename(dirname($sourcefile));
        if (! -e $outdir)
        {
            mkdir($outdir) or $self->__die("mkdir $outdir: $!");
        }
        elsif (! -d $outdir)
        {
            $self->__die("Output dir $outdir exists but is not a directory.");
        }
	# If file is in current dir ".", then $outdir = ".." above and passes without error
    }

    return 1; # success
}

# Given a file name, init the xml object to parse
sub __init_sourcexml
{
    my($self, $filename) = @_;
    $self->{sourcexml} =  XMLin($filename, ForceArray => [qw(ThingDef li)])
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
    my($self, $sourcefile) = @_;
    $sourcefile =~ s/(?:-REF)?\.txt/.xml/;

    $self->{patchfile} = basename(dirname($sourcefile)) . "/" . basename($sourcefile);
    #open($self->{patchfh}, ">", $self->{patchfile})
    $self->{patchfh} = new IO::File(">" . $self->{patchfile})
        or $self->__die("Failed to open/write $self->{patchfile}: $!\n");

    return $self->{patchfile};
}

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

sub __close_patchfile
{
    my($self) = @_;
    $self->{patchfh} && $self->{patchfh}->close() || $self->__warn("close $self->{patchfile}: $!");
}

# Common patch contents
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

sub __print_patch_closer
{
    my($self) = @_;

    $self->__print_patch(<<EOF);
  </operations>  <!-- end sequence -->
  </Operation>   <!-- end sequence -->

</Patch>

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

# Messages
sub __info { shift; print(@_, "\n"); }
sub __warn { my($self, @msg) = @_; warn((ref($self) || $self), "> WARN: ", @msg, "\n"); }
sub __die  { my($self, @msg) = @_; warn((ref($self) || $self), "> ERR: ", @msg, "\n"); exit(1); }

1;

__END__

