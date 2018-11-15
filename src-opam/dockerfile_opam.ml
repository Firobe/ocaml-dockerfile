(*
 * Copyright (c) 2015 Anil Madhavapeddy <anil@recoil.org>
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF USE, DATA OR PROFITS, WHETHER IN AN
 * ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING OUT OF
 * OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 *
 *)

(** OPAM-specific Dockerfile rules *)

open Dockerfile
module Linux = Dockerfile_linux
module D = Dockerfile_distro
module OV = Ocaml_version

let run_as_opam fmt = Linux.run_as_user "opam" fmt

let install_opam_from_source ?(prefix= "/usr/local") ~branch () =
  Linux.Git.init () @@
  run "git clone -b %s git://github.com/ocaml/opam /tmp/opam" branch @@ 
  Linux.run_sh
       "cd /tmp/opam && make cold && mkdir -p %s/bin && cp /tmp/opam/opam %s/bin/opam && cp /tmp/opam/opam-installer %s/bin/opam-installer && chmod a+x %s/bin/opam %s/bin/opam-installer && rm -rf /tmp/opam"
       prefix prefix prefix prefix prefix

let install_bubblewrap_from_source ?(prefix="/usr/local") () =
  let rel = "0.3.1" in
  let file = Fmt.strf "bubblewrap-%s.tar.xz" rel in
  let url = Fmt.strf "https://github.com/projectatomic/bubblewrap/releases/download/v%s/bubblewrap-%s.tar.xz" rel rel in
  run "curl -OL %s" url @@
  run "tar xf %s" file @@
  run "cd bubblewrap-%s && ./configure --prefix=%s && make && sudo make install" rel prefix @@
  run "rm -rf %s bubblewrap-%s" file rel

let install_bubblewrap_wrappers =
  (* Enable bubblewrap *)
  run "echo 'wrap-build-commands: []' > ~/.opamrc-nosandbox" @@
  run "echo 'wrap-install-commands: []' >> ~/.opamrc-nosandbox" @@
  run "echo 'wrap-remove-commands: []' >> ~/.opamrc-nosandbox" @@
  run "echo 'required-tools: []' >> ~/.opamrc-nosandbox" @@
  run "echo '#!/bin/sh' > /home/opam/opam-sandbox-disable" @@
  run "echo 'cp ~/.opamrc-nosandbox ~/.opamrc' >> /home/opam/opam-sandbox-disable" @@
  run "echo 'echo --- opam sandboxing disabled' >> /home/opam/opam-sandbox-disable" @@
  run "chmod a+x /home/opam/opam-sandbox-disable" @@
  run "sudo mv /home/opam/opam-sandbox-disable /usr/bin/opam-sandbox-disable" @@
  (* Disable bubblewrap *)
  run "echo 'wrap-build-commands: [\"%%{hooks}%%/sandbox.sh\" \"build\"]' > ~/.opamrc-sandbox" @@
  run "echo 'wrap-install-commands: [\"%%{hooks}%%/sandbox.sh\" \"install\"]' >> ~/.opamrc-sandbox" @@
  run "echo 'wrap-remove-commands: [\"%%{hooks}%%/sandbox.sh\" \"remove\"]' >> ~/.opamrc-sandbox" @@
  run "echo '#!/bin/sh' > /home/opam/opam-sandbox-enable" @@
  run "echo 'cp ~/.opamrc-sandbox ~/.opamrc' >> /home/opam/opam-sandbox-enable" @@
  run "echo 'echo --- opam sandboxing enabled' >> /home/opam/opam-sandbox-enable" @@
  run "chmod a+x /home/opam/opam-sandbox-enable" @@
  run "sudo mv /home/opam/opam-sandbox-enable /usr/bin/opam-sandbox-enable"
   
let header ?maintainer img tag =
  let maintainer =
    match maintainer with
    | None -> empty
    | Some t -> Dockerfile.maintainer "%s" t
  in
  comment "Autogenerated by OCaml-Dockerfile scripts" @@ from ~tag img
  @@ maintainer


(* Apk based Dockerfile *)
let apk_opam2 ?(labels= []) ~distro ~tag () =
  header distro tag @@ label (("distro_style", "apk") :: labels)
  @@ Linux.Apk.install "build-base bzip2 git tar curl ca-certificates openssl"
  @@ install_opam_from_source ~branch:"2.0" ()
  @@ run "strip /usr/local/bin/opam*"
  @@ from ~tag distro
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam"] ~dst:"/usr/bin/opam" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-installer"]
       ~dst:"/usr/bin/opam-installer" ()
  @@ Linux.Apk.dev_packages ()
  @@ Linux.Apk.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()
  @@ run
       "git clone git://github.com/ocaml/opam-repository /home/opam/opam-repository"


(* Debian based Dockerfile *)
let apt_opam2 ?(labels= []) ~distro ~tag () =
  header distro tag @@ label (("distro_style", "apt") :: labels)
  @@ Linux.Apt.install "build-essential curl git libcap-dev sudo"
  @@ install_bubblewrap_from_source ()
  @@ install_opam_from_source ~branch:"2.0" ()
  @@ from ~tag distro
  @@ copy ~from:"0" ~src:["/usr/local/bin/bwrap"] ~dst:"/usr/bin/bwrap" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam"] ~dst:"/usr/bin/opam" ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/opam-installer"]
       ~dst:"/usr/bin/opam-installer" ()
  @@ run "ln -fs /usr/share/zoneinfo/Europe/London /etc/localtime"
  @@ Linux.Apt.dev_packages ()
  @@ Linux.Apt.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()
  @@ run
       "git clone git://github.com/ocaml/opam-repository /home/opam/opam-repository"


(* RPM based Dockerfile *)
let yum_opam2 ?(labels= []) ~distro ~tag () =
  header distro tag @@ label (("distro_style", "rpm") :: labels)
  @@ run "touch /var/lib/rpm/*"
  @@ Linux.RPM.install "yum-plugin-ovl"
  @@ Linux.RPM.update 
  @@ Linux.RPM.dev_packages ~extra:"which tar curl xz libcap-devel openssl" ()
  @@ install_bubblewrap_from_source ()
  @@ install_opam_from_source ~prefix:"/usr" ~branch:"2.0" ()
  @@ from ~tag distro @@ Linux.RPM.install "yum-plugin-ovl" @@ Linux.RPM.update
  @@ Linux.RPM.dev_packages ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/bwrap"] ~dst:"/usr/bin/bwrap" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam"] ~dst:"/usr/bin/opam" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam-installer"]
       ~dst:"/usr/bin/opam-installer" ()
  @@ run
       "sed -i.bak '/LC_TIME LC_ALL LANGUAGE/aDefaults    env_keep += \"OPAMYES OPAMJOBS OPAMVERBOSE\"' /etc/sudoers"
  @@ Linux.RPM.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()
  @@ run
       "git clone git://github.com/ocaml/opam-repository /home/opam/opam-repository"


(* Zypper based Dockerfile *)
let zypper_opam2 ?(labels= []) ~distro ~tag () =
  header distro tag @@ label (("distro_style", "zypper") :: labels)
  @@ Linux.Zypper.dev_packages ()
  @@ install_bubblewrap_from_source ()
  @@ install_opam_from_source ~prefix:"/usr" ~branch:"2.0" ()
  @@ from ~tag distro
  @@ Linux.Zypper.dev_packages ()
  @@ copy ~from:"0" ~src:["/usr/local/bin/bwrap"] ~dst:"/usr/bin/bwrap" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam"] ~dst:"/usr/bin/opam" ()
  @@ copy ~from:"0" ~src:["/usr/bin/opam-installer"]
       ~dst:"/usr/bin/opam-installer" ()
  @@ Linux.Zypper.add_user ~uid:1000 ~sudo:true "opam"
  @@ install_bubblewrap_wrappers @@ Linux.Git.init ()
  @@ run
       "git clone git://github.com/ocaml/opam-repository /home/opam/opam-repository"

let gen_opam2_distro ?labels d =
  let distro, tag = D.base_distro_tag d in
  let fn = match D.package_manager d with
  | `Apk -> apk_opam2 ?labels ~tag ~distro ()
  | `Apt -> apt_opam2 ?labels ~tag ~distro ()
  | `Yum -> yum_opam2 ?labels ~tag ~distro ()
  | `Zypper -> zypper_opam2 ?labels ~tag ~distro ()
  in (D.tag_of_distro d, fn)

(* Generate archive mirror *)
let opam2_mirror (hub_id: string) =
  header hub_id "alpine-3.7-ocaml-4.06"
  @@ run "sudo apk add --update bash m4"
  @@ workdir "/home/opam/opam-repository" @@ run "git checkout master"
  @@ run "git pull origin master"
  @@ run "opam init -a /home/opam/opam-repository" @@ env [("OPAMJOBS", "24")]
  @@ run "opam install -yj4 cohttp-lwt-unix" @@ run "opam admin cache"

let all_ocaml_compilers hub_id arch distro =
  let distro_tag = D.tag_of_distro distro in
  let compilers =
    OV.Releases.recent |>
    List.filter (fun ov -> D.distro_supported_on arch ov distro) |>
    List.map (fun t ->
      run "opam switch create %s %s"
        (OV.(to_string (with_patch (with_variant t None) None))) (OV.Opam.V2.name t)) |>
      (@@@) empty
  in
  let d =
    header hub_id (Fmt.strf "%s-opam" distro_tag)
    @@ workdir "/home/opam/opam-repository" @@ run "git pull origin master"
    @@ run "opam-sandbox-disable"
    @@ run "opam init -k git -a /home/opam/opam-repository --bare"
    @@ compilers 
    @@ run "opam switch %s" (OV.(to_string (with_patch OV.Releases.latest None)))
    @@ entrypoint_exec ["opam"; "config"; "exec"; "--"]
    @@ run "opam install -y depext"
    @@ env ["OPAMYES","1"]
    @@ cmd "bash"
  in
  (Fmt.strf "%s" distro_tag, d)

let tag_of_ocaml_version ov =
  Ocaml_version.with_patch ov None |>
  Ocaml_version.to_string |>
  String.map (function '+' -> '-' | x -> x)

let separate_ocaml_compilers hub_id arch distro =
  let distro_tag = D.tag_of_distro distro in
  OV.Releases.recent_with_dev |> List.filter (fun ov -> D.distro_supported_on arch ov distro) 
  |> List.map (fun ov ->
         let add_remote =
           if List.mem ov OV.Releases.dev then
             run "opam repo add ocaml-dev git://github.com/ocaml/ocaml-pr-repository --set-default"
           else empty in
         let default_switch_name = OV.(with_patch (with_variant ov None) None |> to_string) in
         let variants =
           OV.Opam.V2.switches arch ov |>
           List.map (fun t -> run "opam switch create %s %s" (OV.(to_string (with_patch t None))) (OV.Opam.V2.name t)) |>
          (@@@) empty
         in
         let d =
           header hub_id (Fmt.strf "%s-opam" distro_tag)
           @@ workdir "/home/opam/opam-repository"
           @@ run "opam-sandbox-disable"
           @@ run "opam init -k git -a /home/opam/opam-repository --bare"
           @@ add_remote
           @@ variants
           @@ run "opam switch %s" default_switch_name
           @@ run "opam install -y depext"
           @@ env ["OPAMYES","1"]
           @@ entrypoint_exec ["opam"; "config"; "exec"; "--"]
           @@ cmd "bash"
         in
         (Fmt.strf "%s-ocaml-%s" distro_tag (tag_of_ocaml_version ov), d) )


let bulk_build prod_hub_id distro ocaml_version opam_repo_rev =
  let use_main_tag =
    (OV.extra ocaml_version <> None) ||
    (* TODO pass arch up as a param *)
    (List.mem (D.resolve_alias distro) (D.active_tier1_distros `X86_64)) in
  let tag =
    if use_main_tag then
      Fmt.strf "%s-ocaml-%s" (D.tag_of_distro distro) OV.(to_string (with_variant ocaml_version None))
    else 
      D.tag_of_distro distro
  in
  header prod_hub_id tag
  @@ run "opam switch %s" (OV.to_string ocaml_version)
  @@ env [("OPAMYES", "1")]
  @@ workdir "/home/opam/opam-repository"
  @@ run "git pull origin master"
  @@ run "git checkout %s" opam_repo_rev
  @@ run "opam update"
  @@ run "opam depext -iy dune ocamlfind"

let deprecated =
  header "alpine" "latest"
  @@ run "echo 'This container is now deprecated and no longer supported. Please see https://github.com/ocaml/infrastructure/wiki/Containers for the latest supported tags.  Try to use the longer term supported aliases instead of specific distribution versions if you want to avoid seeing this message in the future.' && exit 1"

let multiarch_manifest ~target ~platforms =
  let ms =
    List.map
      (fun (image, arch) ->
        Fmt.strf
          "  -\n    image: %s\n    platform:\n      architecture: %s\n      os: linux"
          image arch)
      platforms
    |> String.concat "\n"
  in
  Fmt.strf "image: %s\nmanifests:\n%s" target ms
