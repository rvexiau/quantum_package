open Qputils;;
open Qptypes;;
open Core.Std;;

(** Interactive editing of the input.

WARNING 
This file is autogenerad by
`${QP_ROOT}/script/ezfio_interface/ei_handler.py`
*)


(** Keywords used to define input sections *)
type keyword = 
| Ao_basis
| Determinants_by_hand
| Electrons
| Mo_basis
| Nuclei
| Perturbation
| Hartree_fock
| Pseudo
| Integrals_bielec
| Determinants
| Properties
;;


let keyword_to_string = function
| Ao_basis              -> "AO basis"
| Determinants_by_hand  -> "Determinants_by_hand"
| Electrons             -> "Electrons"
| Mo_basis              -> "MO basis"
| Nuclei                -> "Molecule"
| Perturbation -> "Perturbation"
| Hartree_fock -> "Hartree_fock"
| Pseudo -> "Pseudo"
| Integrals_bielec -> "Integrals_bielec"
| Determinants -> "Determinants"
| Properties -> "Properties"
;;



(** Create the header of the temporary file *)
let file_header filename = 
  Printf.sprintf  "
==================================================================
                       Quantum Package
==================================================================

Editing file `%s`

" filename
;;
  

(** Creates the header of a section *)
let make_header kw =
  let s = keyword_to_string kw in
  let l = String.length s in
  "\n\n"^s^"\n"^(String.init l ~f:(fun _ -> '='))^"\n\n"
;;


(** Returns the rst string of section [s] *)
let get s = 
  let header = (make_header s) in
  let f (read,to_rst) = 
    match read () with
    | Some text -> header ^ (Rst_string.to_string (to_rst text))
    | None      -> ""
  in
  let rst = 
    try
      begin
         let open Input in
         match s with
         | Mo_basis ->
           f Mo_basis.(read, to_rst)
         | Electrons ->
           f Electrons.(read, to_rst)
         | Nuclei ->
           f Nuclei.(read, to_rst)
         | Ao_basis ->
           f Ao_basis.(read, to_rst)
         | Determinants_by_hand ->
           f Determinants_by_hand.(read, to_rst)
         | Perturbation ->
           f Perturbation.(read, to_rst)
         | Hartree_fock ->
           f Hartree_fock.(read, to_rst)
         | Pseudo ->
           f Pseudo.(read, to_rst)
         | Integrals_bielec ->
           f Integrals_bielec.(read, to_rst)
         | Determinants ->
           f Determinants.(read, to_rst)
         | Properties ->
           f Properties.(read, to_rst)
      end
    with
    | Sys_error msg -> (Printf.eprintf "Info: %s\n%!" msg ; "")
  in 
  rst
;;


(** Applies the changes from the string [str] corresponding to section [s] *)
let set str s = 
  let header = (make_header s) in
  match String.substr_index ~pos:0 ~pattern:header str with
  | None -> ()
  | Some idx -> 
    begin
      let index_begin = idx + (String.length header) in
      let index_end   = 
        match ( String.substr_index ~pos:(index_begin+(String.length header)+1)
          ~pattern:"==" str) with
          | Some i -> i
          | None -> String.length str
      in
      let l = index_end - index_begin in
      let str = String.sub ~pos:index_begin ~len:l str
      |> Rst_string.of_string
      in
      let write (of_rst,w) s =
        try
        match of_rst str with
        | Some data -> w data
        | None -> ()
        with
        | _ -> (Printf.eprintf "Info: Read error in %s\n%!"
               (keyword_to_string s); ignore (of_rst str) )
      in
      let open Input in
        match s with
        | Perturbation -> write Perturbation.(of_rst, write) s
        | Hartree_fock -> write Hartree_fock.(of_rst, write) s
        | Pseudo -> write Pseudo.(of_rst, write) s
        | Integrals_bielec -> write Integrals_bielec.(of_rst, write) s
        | Determinants -> write Determinants.(of_rst, write) s
        | Properties -> write Properties.(of_rst, write) s
        | Electrons        -> write Electrons.(of_rst, write) s
        | Determinants_by_hand     -> write Determinants_by_hand.(of_rst, write) s
        | Nuclei           -> write Nuclei.(of_rst, write) s
        | Ao_basis         -> () (* TODO *)
        | Mo_basis         -> () (* TODO *)
    end 
;;


(** Creates the temporary file for interactive editing *)
let create_temp_file ezfio_filename fields =
  let temp_filename  = Filename.temp_file "qp_edit_" ".rst" in
  begin
      Out_channel.with_file temp_filename ~f:(fun out_channel ->
        (file_header ezfio_filename) :: (List.map ~f:get fields) 
        |> String.concat ~sep:"\n" 
        |> Out_channel.output_string out_channel 
      )
  end
  ; temp_filename
;;



let run check_only ezfio_filename =

  (* Open EZFIO *)
  if (not (Sys.file_exists_exn ezfio_filename)) then
    failwith (ezfio_filename^" does not exists");

  Ezfio.set_file ezfio_filename;

  (*
  let output = (file_header ezfio_filename) :: (
    List.map ~f:get [
      Ao_basis ; 
      Mo_basis ; 
    ])
   in
  String.concat output
  |> print_string
  *)
  
  let tasks = [
      Nuclei ;
      Ao_basis;
      Electrons ;
      Perturbation ; 
      Hartree_fock ; 
      Pseudo ; 
      Integrals_bielec ; 
      Determinants ; 
      Properties ; 
      Mo_basis;
      Determinants_by_hand ;
  ]
  in

  (* Create the temp file *)
  let temp_filename = create_temp_file ezfio_filename tasks in

  (* Open the temp file with external editor *)
  let editor = 
    match Sys.getenv "EDITOR" with
    | Some editor -> editor
    | None -> "vi"
  in

  match check_only with
  | true  -> ()
  | false -> 
    Printf.sprintf "%s %s" editor temp_filename 
    |> Sys.command_exn 
  ;

  (* Re-read the temp file *)
  let temp_string  =
    In_channel.with_file temp_filename ~f:(fun in_channel ->
      In_channel.input_all in_channel) 
  in
  List.iter ~f:(fun x -> set temp_string x) tasks;

  (* Remove temp_file *)
  Sys.remove temp_filename;
;;


(** Create a backup file in case of an exception *)
let create_backup ezfio_filename =
  Printf.sprintf "
    rm -f %s/backup.tgz ;
    tar -zcf .backup.tgz %s && mv .backup.tgz %s/backup.tgz
  "
    ezfio_filename ezfio_filename ezfio_filename
  |> Sys.command_exn
;;


(** Restore the backup file when an exception occuprs *)
let restore_backup ezfio_filename =
  Printf.sprintf "tar -zxf %s/backup.tgz"
    ezfio_filename 
  |> Sys.command_exn
;;


let spec =
  let open Command.Spec in
  empty 
  +> flag "-c" no_arg
     ~doc:"Checks the input data"
(*
  +> flag "o" (optional string)
     ~doc:"Prints output data"
*)
  +> anon ("ezfio_file" %: string)
;;

let command = 
    Command.basic 
    ~summary: "Quantum Package command"
    ~readme:(fun () ->
      "
Edit input data
      ")
    spec
(*    (fun i o ezfio_file () -> *)
    (*fun ezfio_file () -> 
       try 
           run ezfio_file
       with
       | _ msg -> print_string ("\n\nError\n\n"^msg^"\n\n")
    *)
    (fun c ezfio_file () ->
       try
          run c ezfio_file ;
          (* create_backup ezfio_file; *)
       with
       | Failure exc 
       | Invalid_argument exc as e -> 
         begin
           Printf.eprintf "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n\n";
           Printf.eprintf "%s\n\n" exc;
           Printf.eprintf "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n\n";
           (* restore_backup ezfio_file; *) 
           raise e
         end
       | Assert_failure (file, line, ch) as e ->
         begin
           Printf.eprintf "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n\n";
           Printf.eprintf "Assert error in file $QP_ROOT/ocaml/%s, line %d, character %d\n\n" file line ch;
           Printf.eprintf "=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-\n\n";
           (* restore_backup ezfio_file; *)
           raise e
         end
    )
;;

let () =
  Command.run command;
  exit 0
;;



