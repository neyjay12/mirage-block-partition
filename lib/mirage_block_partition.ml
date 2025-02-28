module Make(B : Mirage_block.S) = struct
 
  type t = {
    b : B.t;
    sector_size : int;
    (* inclusive *)
    sector_start : int64;
    (* exclusive *)
    sector_end : int64;
  }
  
  type nonrec error = [ 
    | Mirage_block.error
    | `Block of B.error
    | `Out_of_bounds ]
  type nonrec write_error = [
    | Mirage_block.write_error
    | `Block of B.write_error
    | `Out_of_bounds ]

  let pp_error ppf = function
    | `Block e | (#Mirage_block.error as e) -> B.pp_error ppf e
    | `Out_of_bounds -> Fmt.pf ppf "Operation out of partition bounds"
    

  let pp_write_error ppf = function
    | `Block e | (#Mirage_block.write_error as e) -> B.pp_write_error ppf e
    | `Out_of_bounds -> Fmt.pf ppf "Operation out of partition bounds"
    

  let get_info b =
    let size_sectors = Int64.(sub b.sector_end b.sector_start) in
    Lwt.map (fun info -> { info with Mirage_block.size_sectors })
      (B.get_info b.b)
      

  let get_offset { sector_start; _ } = sector_start


  (* Verify that the working area of a read or write fits within the partition. *)
  let is_within b sector_start buffers =
    let buffers_len =
      List.fold_left (fun acc cs -> Int64.(add acc (of_int (Cstruct.length cs))))
        0L buffers
    in
    let num_sectors =
      let sector_size = Int64.of_int b.sector_size in
      Int64.(div (add buffers_len (pred sector_size))
               sector_size)
    in
    let sector_start = Int64.add sector_start b.sector_start in
    let sector_end = Int64.add sector_start num_sectors in
    sector_start >= b.sector_start && sector_end <= b.sector_end

(* Perform a read operation, checking to determine if it is inside the partition's limitations or bounds*)
  let read b sector_start buffers =
    (* XXX: here and in [write] we rely on the underlying block device to check
       for alignment issues of [buffers]. *)
    if is_within b sector_start buffers
    then
      B.read b.b (Int64.add b.sector_start sector_start) buffers
      |> Lwt_result.map_error (fun b -> `Block b)
    else
      Lwt.return (Error `Out_of_bounds)

  (* Perform a write operation, checking to see if it is within the partition's boundaries or limitations *)
  let write b sector_start buffers =
    if is_within b sector_start buffers
    then
      B.write b.b (Int64.add b.sector_start sector_start) buffers
      |> Lwt_result.map_error (fun b -> `Block b)
    else
      Lwt.return (Error `Out_of_bounds)

  let partition b ~sector_size ~sector_start ~sector_end ~first_sectors =
    if first_sectors < 0L then
      raise (Invalid_argument "Partition point before device");
    let sector_mid = Int64.add sector_start first_sectors in
    if sector_mid > sector_end then
      raise (Invalid_argument "Partition point beyond device");
    ({ b; sector_size; sector_start; sector_end = sector_mid },
        { b; sector_size; sector_start = sector_mid; sector_end })

  let connect first_sectors b =
    let open Lwt.Syntax in
    let+ { Mirage_block.sector_size; size_sectors = sector_end; _ } = B.get_info b in
    let sector_start = 0L in
    partition b ~sector_size ~sector_start ~sector_end ~first_sectors

  let subpartition first_sectors { b; sector_size; sector_start; sector_end } =
    partition b ~sector_size ~sector_start ~sector_end ~first_sectors

  let disconnect b =
    (* XXX disconnect both?! *)
    B.disconnect b.b
end
