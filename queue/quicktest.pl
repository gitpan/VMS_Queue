use VMS::Queue;
@FileList = VMS::Queue::file_list('66');
$foo = @FileList;
print "got $foo files\n";
foreach $filehashref (@FileList) {
  foreach $keyval (keys %$filehashref) {
    print "$keyval is $filehashref->{$keyval}\n";
  }
}

