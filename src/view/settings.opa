/*
 * PEPS is a modern collaboration server
 * Copyright (C) 2015 MLstate
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU Affero General Public License as published
 * by the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU Affero General Public License for more details.
 *
 * You should have received a copy of the GNU Affero General Public License
 * along with this program.  If not, see <http://www.gnu.org/licenses/>.
 */


package com.mlstate.webmail.view

SettingsView = {{

  /** {1} Utils. */

  log = Log.info("SettingsView: ", _)

  /**
   * {1} Various settings.
   * {2} Browser notifications.
   */

  @client
  enable_browser_notifications(_) =
    HTML5_Notifications.request(b ->
      if b then Content.reset()
    ) |> ignore

  @client
  check_html5_notifications(_) =
    if not(HTML5_Notifications.support()) then
      #notif_status <- @intl("Your browser does not support notifications. Please consider upgrading your browser.")
    else if not(HTML5_Notifications.enabled()) then
      #html5_notifications <- <>{@intl("You need to accept notifications in your browser.")} <a onclick={enable_browser_notifications}>{@intl("Click here to request notifications.")}</a></>

  /** {2} Signature input. */

  @client @async
  do_save_signature(_ : Dom.event) =
    sgn = Dom.get_value(#user_signature)
    SettingsController.save_user_signature(sgn, profile_updated)

  profile_updated(res) =
    Notifications.info(AppText.Profile(), <>{@intl("Profile updated")}</>)

  /** {2} Profile update. */

  Profile = {{

    /**
     * Show a password input form with three prompts for the old password,
     * the new password and a password repeat.
     */
    @client passwordInput(_evt) =
      // Check inputs, and resut of callback before destroying the modal.
      doconfirm(_evt) =
        oldpassword = Dom.get_value(#oldpassword)
        newpassword = Dom.get_value(#newpassword)
        repeatpassword = Dom.get_value(#repeatpassword)

        if (newpassword == repeatpassword && validate_password(newpassword)) then
          SettingsController.save_user_password(oldpassword, newpassword,
            | {success= _} ->
              do Dom.remove(#passwordmodal)
              Notifications.info(AppText.Profile(), <>{@intl("Password updated")}</>)
            | ~{failure} ->
              Notifications.notify("passwordnotify", AppText.password(), <>{failure}</>, {error})
          )
        else if (newpassword == repeatpassword) then
          Notifications.notify("passwordnotify", AppText.password(), <>{@intl("Passwords do not match")}</>, {error})
        else Notifications.notify("passwordnotify", AppText.password(), <>{@intl("Invalid new password")}</>, {error})

      // Destroy the modal and return with no value.
      docancel(_evt) =
        Dom.remove(#passwordmodal)

      prompt =
        <>
        <div id="passwordnotify"/>
        {Form.wrapper(
          Form.form_group(
            <input type=password id="oldpassword" class="form-control" placeholder="{@intl("Previous password")}"></input>
          ) <+>
          Form.form_group(
            <input type=password id="newpassword" class="form-control" placeholder="{@intl("New password")}"></input>
          ) <+>
          Form.form_group(
            <input type=password id="repeatpassword" class="form-control" placeholder="{@intl("Repeat password")}"></input>
          )
        , true)}
        </>
      ok = WB.Button.make({button= <>{AppText.Ok()}</> callback= doconfirm}, [{primary}])
      cancel = WB.Button.make({button= <>{AppText.Cancel()}</> callback= docancel}, [{`default`}])
      modal =
        Modal.make("passwordmodal", <>{@intl("Change password")}</>,
          prompt, <>{cancel}{ok}</>,
          {Modal.default_options with backdrop= false static= false keyboard= false}
        )
      do #main +<- modal // APPEND the modal so it appears in front of other modals.
      do Modal.show(#passwordmodal)
      do Scheduler.sleep(500, -> Dom.give_focus(#oldpassword))
      do Dom.bind(#passwordmodal, {custom= "hidden.bs.modal"}, docancel) |> ignore
      Dom.bind_with_options(#passwordinput, {newline}, doconfirm, [{stop_propagation}, {prevent_default}]) |> ignore


    // TODO: better validation, ideally according to rules defined by super admin.
    @client
    validate_password =
    | "" -> false
    | _ -> true

    @server_private
    build(state) =
      match (ContactController.self()) with
      | {failure= msg} ->
        <div>{Notifications.build(AppText.Profile(), <>{msg}</>, {error})}</div>
      | {success=contact} ->
        options = {
          cancel= false reset=true actions= false
          format= UserController.format_contact
        }
        display = ContactView.edit_contact(contact, options)
        password = WB.Button.make({button= <><i class="fa fa-refresh"/> {@intl("Change password")}</> callback=passwordInput}, [{`default`}])
          |> Xhtml.update_class("btn-sm", _)
        Utils.panel_default(
          Utils.panel_heading(AppText.Profile()) <+>
          Utils.panel_body(
            <div class="panel-body-action-top">{password}</div> <+>
            display
            )
        )

  }} // END PROFILE

  /** {1} Message folders. */

  @publish @async
  refresh_folders(state) =
    if (Login.is_logged(state)) then
      FolderController.refresh(state.key)
  @client @async
  do_refresh_folders(state, _evt) =
    refresh_folders(state)

  @server_private
  build_signature(state) =
    match User.get(state.key)
    {none} -> <>{AppText.login_please()}</>
    {some=user} ->
      Utils.panel_default(
        Utils.panel_heading(AppText.Signature()) <+>
        Utils.panel_body(
          <form role="form">
            <div class="form-group">
              <textarea id=#user_signature rows="10" cols="80" class="form-control">
                {user.sgn}
              </textarea>
            </div>
            <div class="form-group">
              {WB.Button.make({link=<>{AppText.save()}</> href=none
              callback=do_save_signature}, [{primary}])}
            </div>
          </form>
      ))

  WI18n = {{

    @private localeToString(locale) =
      match locale.language with
      | "en" -> "English"
      | "fr" -> "Français"
      | "ja" -> "日本語"
      | s -> s
      end

    @private localeToHtml(locale) =
      do Log.notice("[Settings]", "localeToHtml: {locale}")
      flag(code) = <img src="/resources/img/{code}.gif"/>
      flag =
        match locale.language with
        | "en" -> if (locale.region == "") then flag("US") else flag(locale.region)
        | "fr" -> if (locale.region == "") then flag("FR") else flag(locale.region)
        | _    -> <></>
        end
      <>{flag} {localeToString(locale)}</>

    @private @client setLocale(id, _evt) =
      locale = Dom.get_value(#{id})
      match Intl.parseLocale(locale) with
      | {some= locale} ->
        do Intl.setLocale(locale)
        do SettingsController.setLocale(locale)
        Client.reload()
      | _ -> void
      end

    @server_private localeSelector() =
      id = Dom.fresh_id()
      entry(locale) = <option value="{Intl.localeToString(locale)}">{localeToString(locale)}</option>
      // Multiple option selection.
      <div class="input-group">
        <span class="input-group-addon">
          {localeToHtml(@locale)}
        </span>
        <select class="form-control" id={id} onchange={setLocale(id, _)}>
          <option>{@intl("Change language")}</option>
          {List.map(entry, Intl.listLocales())}
        </select>
      </div>

  }} // END WI18N

  /** preferences **/

  @client @async
  save_preferences_callback(state, view, res) =
    do Button.reset(#save_preferences_button)
    match res
    | {success= view} ->
      urn = URN.get()
      do SidebarView.refresh(state, urn)
      do if (view == {icons})
      then Dom.remove_class(#main, "narrow")
      else Dom.add_class(#main, "narrow")
      Notifications.info(AppText.Display(), <>{@intl("Preferences saved")}</>)
    | {failure=s} -> Notifications.error(AppText.Display(), <>{s}</>)

  @client @async
  do_save_preferences(state, _:Dom.event) =
    do Button.loading(#save_preferences_button)
    view = if Dom.select_id("icons_view_user") |> Dom.is_checked(_) then {icons} else {folders}
    notifications = Dom.is_checked(#notifications_user)
    search_includes_send = Dom.is_checked(#search_includes_send)
    onboarding = Dom.is_checked(#onboarding)
    SettingsController.save_user_preferences(view, notifications, search_includes_send, onboarding,
      save_preferences_callback(state, view, _))

  @server_private
  check_radio_btn(view:Sidebar.view, ref, xhtml) =
    if view == ref then Xhtml.add_attribute_unsafe("checked", "checked", xhtml)
    else xhtml

  @server_private
  build_user_preferences(state:Login.state) =
    (view, notifs, sis, onboarding) = SettingsController.get_user_preferences(state.key)
    icons_btn =
      <label for="icons_view_user" class="radio-inline">
        {<input type="radio" name="view" id=#icons_view_user/>
         |> check_radio_btn(view, {icons}, _)}
        {@intl("Only icons")}
      </label>
    folders_btn =
      <label for="folders_view_user" class="radio-inline">
        {<input type="radio" name="view" id=#folders_view_user/>
         |> check_radio_btn(view, {folders}, _)}
        {@intl("Basic")}
      </label>
    Utils.panel_default(
      Utils.panel_heading(AppText.Display()) <+>
      Utils.panel_body(
        Form.wrapper(
          Form.label(
            @intl("Default side menu "), "view_user",
            check_radio_btn(view, {icons}, icons_btn) <+>
            check_radio_btn(view, {folders}, folders_btn)
          ) <+>
          <>
          <div class="form-group">
            <label>{@intl("Desktop notifications")}</label>
            <div class="checkbox">
              <label>
                { if notifs then
                    <input type="checkbox" id=#notifications_user checked="checked"/>
                  else
                    <input type="checkbox" id=#notifications_user/>
                } {if notifs then AppText.Enabled() else AppText.Disabled()}
              </label>
              <p class="help-block" id=#html5_notifications onready={check_html5_notifications}></p>
            </div>
          </div>
          <div class="form-group">
            <label>{AppText.search()}</label>
            <div class="checkbox">
              <label>
                { if sis then
                    <input type="checkbox" id=#search_includes_send checked="checked"/>
                  else
                    <input type="checkbox" id=#search_includes_send/>
                } {if sis then @intl("Include Sent") else @intl("Do not include Sent")}
              </label>
            </div>
          </div>
          <div class="form-group">
            <label>{AppText.Onboarding()}</label>
            <div class="checkbox">
              <label>
                { if onboarding then
                    <input type="checkbox" id=#onboarding checked="checked"/>
                  else
                    <input type="checkbox" id=#onboarding/>
                } {if onboarding then AppText.Onboarding() else @intl("Onboarding disabled")}
              </label>
            </div>
          </div>
          <div class="form-group">
            <label class="label-fw">{AppText.folders()}</label>
            {WB.Button.make({button=<><i class="fa fa-repeat-circle-o"/> {AppText.refresh()}</> callback=do_refresh_folders(state, _)}, [])}
          </div>
          </> <+>
          // Form.line_wrapper(
          //   "Notifications", "",
          //   <label id="notif_status" class="checkbox">
          //     {<input type="checkbox" id=#notifications_user></input>
          //      |> (if notifs then Xhtml.add_attribute_unsafe("checked", "checked", _)
          //          else identity)}
          //     <span> {if notifs then "Enabled" else "Disabled"}</span>
          //   </label>
          //   <p id=#html5_notifications onready={check_html5_notifications}></p>
          // ) <+>
          <div class="form-group">{
            WB.Button.make({button=<>{@intl("Save changes")}</> callback=do_save_preferences(state, _)}, [{success}])
            |> Xhtml.add_attribute_unsafe("data-complete-text", @intl("Save changes"), _)
            |> Xhtml.add_attribute_unsafe("data-loading-text", AppText.saving(), _)
            |> Xhtml.add_id(some("save_preferences_button"), _)
          }</div>
        , false)
      )) <+>
      Utils.panel_default(
        Utils.panel_heading(@intl("Language")) <+>
        Utils.panel_body(
          Form.wrapper(<div class="form-group">{WI18n.localeSelector()}</div>, false)
        ))

  @server_private
  build_password(state:Login.state) = <></>

  @server_private
  build(state: Login.state, mode: string, path: Path.t) =
    if (not(Login.is_logged(state))) then
      Content.login_please
    else
      match (mode) with
      | "profile" -> Profile.build(state)
      | "display" -> build_user_preferences(state)
      | "signature" -> build_signature(state)
      | "folders" -> FolderView.build(state)
      | "labels" -> LabelView.build(state, false)
      | _ -> Content.non_existent_resource
      end

  /** Return the action associated with a mode. */
  @private
  action(mode: string) =
    // do log("Selected mode: {mode}")
    match (mode) with
    | "labels" ->
      [{
        text= AppText.create_new_label()
        action= LabelView.create(false, _)
        id= SidebarView.action_id
      }]
    | "folders" ->
      [{
        text= AppText.new_folder()
        action= FolderView.do_create
        id= SidebarView.action_id
      }]
    | _ -> []

  /** {1} Construction of the sidebar. */
  Sidebar: Sidebar.sign = {{

    build(state, options, mode) =
      view = options.view
      onclick(mode, _evt) =
        urn = URN.make({settings=mode}, [])
        // do SidebarView.refresh(state, urn) => already done in Content.refresh
        Content.update(urn, false)

      List.flatten([
        action(mode),
        [ { name="profile"    id="profile"    icon="user-o"           title = AppText.Profile()    onclick = onclick("profile", _) },
          { name="display"    id="display"    icon="desktop-o"        title = AppText.Display()    onclick = onclick("display", _) },
          { name="signature"  id="signature"  icon="pencil-square-o"  title = AppText.Signature()  onclick = onclick("signature", _) },
          { name="folders"    id="folders"    icon="folder-o"         title = AppText.folders()    onclick = onclick("folders", _) },
          { name="labels"     id="labels"     icon="tags-o"           title = AppText.labels()     onclick = onclick("labels", _) } ]
      ])

  }} // END SIDEBAR

}}
