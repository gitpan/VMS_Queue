package VMS::Queue;

use strict;
use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);

require Exporter;
require DynaLoader;

@ISA = qw(Exporter DynaLoader);
# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.
@EXPORT = qw();
@EXPORT_OK = qw();
$VERSION = '0.03';

bootstrap VMS::Queue $VERSION;

#sub new {
#  my($pkg,$pid) = @_;
#  my $self = { __PID => $pid || $$ };
#  bless $self, $pkg; 
#}

#sub one_info { get_one_proc_info_item($_[0]->{__PID}, $_[1]); }
#sub all_info { get_all_proc_info_items($_[0]->{__PID}) }

#sub TIEHASH { my $obj = new VMS::ProcInfo @_; $obj; }
#sub FETCH   { $_[0]->one_info($_[1]); }
#sub EXISTS  { grep(/$_[1]/, proc_info_names()) }

# Can't STORE, DELETE, or CLEAR--this is readonly. We'll Do The Right Thing
# later, when I know what it is...

#sub FIRSTKEY {
#  $_[0]->{__PROC_INFO_ITERLIST} = [ proc_info_names() ];
#  $_[0]->one_info(shift @{$_[0]->{__PROC_INFO_ITERLIST}});
#}
#sub NEXTKEY { $_[0]->one_info(shift @{$_[0]->{__PROC_INFO_ITERLIST}}); }

# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# Below is the stub of documentation for your module. You better edit it!

=head1 NAME

VMS::Queue - Perl extension to manage queues, entries, and forms, and retrieve
queue, entry, and form information.

=head1 SYNOPSIS

  use VMS::Queue;

Queue routines

  @ListOfQueues = queue_list([%Queue_Properties]);
  $Status = stop_queue($Queue_Name);
  $Status = pause_queue($Queue_Name);
  $Status = reset_queue($QueueName);
  $Status = start_queue($Queue_Name);
  $Status = delete_queue($Queue_Name);
  $Status = create_queue(%Queue_Properties); (Unimplemented)
  $Status = modify_queue(%Queue_Properties); (Unimplemented)
  $Status = submit($Queue_Name, %Entry_Properties); (Unimplemented)
  \%QueueProperties = queue_info($Queue_Name);
  \%ValidQueueProperties = queue_properties();
  \%DecodedBitmap = queue_bitmap_decode($AttribName, $Bitmap);

Entry routines

  @ListOfEntries = entry_list([%Entry_Properties]);
  $Status = delete_entry($Entry_Number);
  $Status = hold_entry($Entry_Number);
  $Status = release_entry($Entry_Number);
  $Status = modify_entry(%Entry_Properties); (Unimplemented)
  \%EntryProperties = entry_info($Entry_Number);
  \%ValidEntryProperties = entry_properties();
  \%DecodedBitmap = entry_bitmap_decode($AttribName, $Bitmap);

Form Routines

  @ListOfForms = form_list([%Form_Properties]);
  $Status = create_form(%Form_Properties); (Unimplemented)
  $Status = delete_form($Form_Name);
  $Status = modify_form(%FormProperties); (Unimplemented)
  \%Form_Properties = form_info($Form_Number);
  \%ValidFormProperties = form_properties();
  \%DecodedBitmap = form_bitmap_decode($AttribName, $Bitmap);

Characteristic Routines

  @ListOfCharacteristics = characteristic_list(%Characteristic_Properties);
  $Status = create_characteristic(%Characteristic_Properties); (Unimplemented)
  $Status = delete_characteristic($Characteristic_Name);
  $Status = modify_characteristic(%Characterist_Properties); (Unimplemented)
  \%Characteristic_Properties = characteristic_info($Characteristic_Number);
  \%ValidCharacteristicProperties = characteristic_properties();
  \%DecodedBitmap = characteristic_bitmap_decode($AttribName, $Bitmap);

Queue Manager Routines
  @ListOfQueueManagers = manager_list(%Manager_Properties);
  $Status = stop_manager($Manager_Name);
  $Status = start_manager($Manager_Name);
  $Status = create_manager(%Manager_Properties); (Unimplemented)
  $Status = modify_manager(%Manager_Properties); (Unimplemented)
  $Status = delete_manager(%Manager_Properties);
  \%Manager_Properties = manager_info($Manager_Name);
  \%ValidManagerProperties = manager_properties();
  \%DecodedBitmap = manager_bitmap_decode($AttribName, $Bitmap);

=head1 DESCRIPTION

The VMS::Queue module lets a perl script (running as a user with
appropriate privileges) manage queues, queue entries, forms,
characteristics, and queue managers.

=head2 Queue functions

The queue functions create, delete, manipulate, or list queues. Most
functions take either a queue name or a queue property hash. (With the
exception of submit, which takes an entry property hash) The valid hash
keys for each of the hashes is detailed in the L<"Property hashes">
section.

=item queue_list()

The C<queue_list> function takes an optional C<Queue_Properties> hash, and
returns a list of all the queues that match the properties in the hash. If
no property hash is passed, then a list of all queues is returned.

=item stop_queue()

The C<stop_queue> function stops the passed queue, essentially doing a
STOP/QUEUE from DCL. If the optional second parameter is TRUE, then a
STOP/QUEUE/NEXT is done instead.

=item start_queue()

The C<start_queue> function starts the passed queue.

=item delete_queue()

The C<delete_queue> function deletes the named queue.

=item create_queue()

The C<create_queue> function creates a new queue with the passed
properties.

=item modify_queue()

The C<modify_queue> function modifies the queue referenced in the passed
properties hash. Any property passed in the hash will be applied to the
queue referenced in the hash if at all possible. (Some things can't be
modified for existing queues. In that case, you'll have to delete and
recreate the queue)

=item submit()

C<submit> uses the information in the passed entry_property hash and
creates an entry in the named queue for it.

=item queue_info()

The C<queue_info> function returns a reference to a C<Queue_Property> hash,
with the properties for the queue filled in.

=item queue_properties()

This funnction returns a reference to a hash whose keys are the valid keys
for a C<queue_property> hash. The values for the keys are currently
undefined, though they might mean something in a future release.

=item queue_bitmap_decode()

Takes an attribute and an integer, and returns a reference to a hash. The
properties are in the keys, while the values are C<INPUT>, C<OUTPUT>, or
C<INPUT,OUTPUT>. C<INPUT> properties may be specified to a call that takes
a queue_propery hash, while C<OUTPUT> properties may be returned by a call
that returns a queue_property hash.

=head2 Entry functions

The entry functions provide a way to manipulate queue entries. 

=item entry_list()

This function provides a list of all the entries that match the optional
C<entry_properties> hash. If no hash is passed, all entries in all queues
are returned.

=item delete_entry()

Deletes the entry identified by the passed entry number.

=item hold_entry()

Marks the passed entry as on hold.

=item release_entry()

Releases the passed entry.

=item modify_entry()

Modifies the entry, as identified in the entry_properties hash, with the
new properties in the hash. Not all properties for a queue entry are
modifiable, so this might throw an error.

=item entry_info()

Returns an entry_property hash with the properties for the passed entry.

=item entry_properties()

Returns the valid properties that can be in an entry_property hash. The
properties are in the keys, while the values is a hashref with these four
elements: C<INPUT_INFO>, C<OUTPUT_INFO>, C<INPUT_ACTION>, and
C<OUTPUT_ACTION>. Each of these four hash entries will be set to true or
false depending on whether the particular property can be specified as
input or output for an action or info routine. (Action routines do
something--create or delete a queue for example--while info routines return
information on a queue or entry)

=item entry_bitmap_decode()

Takes an attribute and an integer, and returns a reference to a hash. The
hash decodes the bitmap--each key refers to a bit in the bitmap, with the
value set to true or false, depending on the value of the bit in the integer.

=head2 Form functions

The form functions manipulate the form information kept by the queue manager.

=item form_list()

This function returns a list of all forms that match the optional form
properties hash. If no hash is passed, then all forms are returned.

=item create_form()

This function creates a form with the properties specified in the
form_properties hash.

=item delete_form()

This function deletes the form specified.

=item modify_form()

This function applies the properties in the passed form_property hash to
the form referenced in the hash. Not all properties for a form are
changeable, so this function might throw an error.

=item form_info()


=head2 Characteristic functions



=head2 Manager functions



=head2 Property hashes

There are several different property hashes that are passed around, either
directly or by reference.

=item Queue_Properties

=item Entry_Properties

=item Form_Properties

=item Characteristic_properties

=item Manager_Properties

=head1 BUGS

May leak memory. May not, though.

=head1 LIMITATIONS

The documentation isn't finished. (Hey, it's 0.01)

The optional hash for the xxx_list isn't used. (Don't pass it--things'll
screq up)

Bitmap decode functions are implemented, but they don't do anything yet.

=head1 AUTHOR

Dan Sugalski <sugalskd@osshe.edu>

=head1 SEE ALSO

perl(1)

=cut
