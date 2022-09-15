module Make(B : Mirage_block.S) : sig
  include Mirage_block.S
  val connect : B.t -> Mbr.t ->
    ((Mbr.Partition.t * t) list, [> `Overlapping_partitions | `Bad_partition of string ]) result Lwt.t
end
