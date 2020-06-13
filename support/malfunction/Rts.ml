(* These types are made to match the Idris representation *)
module Types = struct
    type world = World

    module IdrisList = struct
        type 'a idris_list =
            | Nil                         (* int 0 *)
            | UNUSED of int               (* block, tag 0 *)
            | Cons of 'a * 'a idris_list  (* block, tag 1 *)

        let rec of_list = function
            | [] -> Nil
            | x :: xs -> Cons (x, of_list xs)

        let rec to_list = function
            | Nil -> []
            | UNUSED _ -> failwith "UNUSED tag in idris list"
            | Cons (x, xs) -> x :: to_list xs
    end
end
open Types
open Types.IdrisList

module IORef = struct
    let write (r : 'a ref) (x : 'a) : unit = r := x
end

module System = struct
    let get_args : string idris_list =
        IdrisList.of_list (Array.to_list Sys.argv)

    let fork_thread (sub : world -> unit) : Thread.t =
        Thread.create sub World
end

module String = struct
    type t = LowLevel.utf8
    type strM = 
        | StrNil               (* int 0 *)
        | UNUSED of int        (* block, tag 0 *)
        | StrCons of char * t  (* block, tag 1 *)

    let cons : char -> t -> t = LowLevel.utf8_cons

    let uncons (s : t) : strM =
        match LowLevel.utf8_uncons s with
        | LowLevel.Nil -> StrNil
        | LowLevel.Cons (x, xs) -> StrCons (x, xs)
        | LowLevel.Malformed -> failwith "uncons: malformed string"

    let length : t -> int =
        let rec go (acc : int) (s : t) =
            match LowLevel.utf8_uncons s with
            | LowLevel.Nil -> 0
            | LowLevel.Cons (_, xs) -> go (acc + 1) xs
            | LowLevel.Malformed -> failwith "uncons: malformed string"
        in go 0

    let head (s : t) : char =
        match LowLevel.utf8_uncons s with
        | LowLevel.Nil -> failwith "Rts.String.head: empty string"
        | LowLevel.Cons (x, _) -> x
        | LowLevel.Malformed -> failwith "Rts.String.head: malformed string"

    let tail (s : t) : t =
        match LowLevel.utf8_uncons s with
        | LowLevel.Nil -> failwith "Rts.String.head: empty string"
        | LowLevel.Cons (_, xs) -> xs
        | LowLevel.Malformed -> failwith "Rts.String.head: malformed string"

    (* pre-allocate a big buffer once and copy all strings in it *)
    let concat (ssi : string idris_list) : string =
        let ss = IdrisList.to_list ssi in
        let total_length = List.fold_left (fun l s -> l + String.length s) 0 ss in
        let result = Bytes.make total_length (Char.chr 0) in
        let rec write_strings (ofs : int) = function
            | IdrisList.Nil -> ()
            | IdrisList.UNUSED _ -> failwith "UNUSED"
            | IdrisList.Cons (s, ss) ->
                let src = Bytes.unsafe_of_string s in
                let len = Bytes.length src in
                Bytes.blit src 0 result ofs len;
                write_strings (ofs+len) ss
          in
        write_strings 0 ssi;
        Bytes.unsafe_to_string result
end

module Debug = struct
    (* %foreign "ML:Rts.Debug.inspect"
     * prim__inspect : (x : a) -> (1 w : %World) -> IORes ()
     *
     * inspect : a -> IO ()
     * inspect x = primIO (prim__inspect x)
     *)
    external inspect : 'ty -> 'a -> unit = "inspect"
end

module File = struct
    type file_ptr =
        | FileR of in_channel
        | FileW of out_channel

    let rec fopen (path : string) (mode : string) (_ : int) : file_ptr option =
        try
            Some(match mode with
            | "r" -> FileR (open_in path)
            | "w" -> FileW (open_out path)
            | "rb" -> FileR (open_in_bin path)
            | "wb" -> FileW (open_out_bin path)
            | _ -> failwith ("unknown file open mode: " ^ mode))
        with Sys_error msg -> None
end

(* some test code *)
module Demo = struct
    external c_hello : int -> string = "c_hello"

    let hello_world (_ : unit) : string =
        print_string "hello from ocaml, getting a secret string from C";
        print_newline ();
        let secret = c_hello 42 in
        print_string "returning from ocaml";
        print_newline ();
        secret
end
