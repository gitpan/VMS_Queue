use VMS::Queue;
$keyhash = VMS::Queue::entry_info('522');
foreach $foo (sort keys %$keyhash) {
  print $foo, '->', %$keyhash->{$foo}, "\n";
  if ($foo eq 'QUEUE_FLAGS') {
    $keyhash2 = VMS::Queue::entry_bitmap_decode('QUEUE_FLAGS',
                                                %$keyhash->{$foo});
    foreach $bar (sort keys %$keyhash2) {
      print "  $bar\-\>", %$keyhash2->{$bar} ? 'yes' : 'no', "\n";
    }
  } elsif ($foo eq 'QUEUE_STATUS') {
    $keyhash3 = VMS::Queue::entry_bitmap_decode('QUEUE_STATUS',
                                                %$keyhash->{$foo});
    foreach $baz (sort keys %$keyhash3) {
      print "  $baz\-\>", %$keyhash3->{$baz} ? 'yes' : 'no', "\n";
    }
  } elsif ($foo eq 'JOB_STATUS') {
    $keyhash4 = VMS::Queue::entry_bitmap_decode('JOB_STATUS',
                                                %$keyhash->{$foo});
    foreach $bazz (sort keys %$keyhash4) {
      print "  $bazz\-\>", %$keyhash4->{$bazz} ? 'yes' : 'no', "\n";
    }
  }
}

