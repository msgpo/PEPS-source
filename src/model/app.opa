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


package com.mlstate.webmail.model

/** The way the application will be inserted into the view. */
type App.display =
  {fullscreen} or // The app iframe will take all of #content
  {sidebar}       // The app is inserted in a toggable sidebar.

/** The application is identified by its consumer key. */
type App.t = {
  string name,
  string url,           // App's base url. It must NOT end with a '/'.
  option(string) icon,  // Icon used in the topbar.
  App.display display,
  // OAuth parameters.
  string oauth_consumer_key,
  string oauth_consumer_secret
}

database App.t /webmail/apps[{oauth_consumer_key}]
database /webmail/apps[_]/display = {fullscreen}

module App {

  private function log(string msg) { Log.notice("[App]", msg) }
  private function warning(string msg) { Log.warning("[App]", msg) }

  /** Random key generator. */
  function genkey() { Random.generic_string("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789",32) }

  function parseDisplay(string display) {
    match (display) {
      case "fullscreen": {fullscreen}
      case "sidebar": {sidebar}
      default: {fullscreen}
    }
  }

  /**
   * Create and add a new application.
   * @param name the application's name
   * @param url the base url, must be a valid url.
   */
  function create(string name, string url, string display) {
    if (exists(name)) {failure: "conflicting app name: {name}"}
    else {
      // Create key / secret pair.
      oauth_consumer_key = genkey()
      oauth_consumer_secret = genkey()
      display = parseDisplay(display)
      app = ~{ name, url, oauth_consumer_key, oauth_consumer_secret, icon: none, display }
      /webmail/apps[oauth_consumer_key == oauth_consumer_key] <- app
      {success: app}
    }
  }

  /** List all existing apps. */
  function list() { DbSet.iterator(/webmail/apps) |> Iter.to_list }
  /** Test app existence. */
  function exists(string name) { DbUtils.option(/webmail/apps[name == name]) |> Option.is_some }
  /** Return the app name. */
  function name(string oauth_consumer_key) { ?/webmail/apps[~{oauth_consumer_key}]/name }

  /** Change the icon of an application. */
  function setIcon(string oauth_consumer_key, string icon) {
    /webmail/apps[oauth_consumer_key == oauth_consumer_key] <- {icon: some(icon); ifexists}
  }

  /** Find an app by its name. */
  function find(string name) { DbUtils.uniq(/webmail/apps[name == name]) }
  /** Fetch an app identified by its consumer key. */
  function get(string oauth_consumer_key) { ?/webmail/apps[~{oauth_consumer_key}] }

  /** Delete an application. */
  function delete(string oauth_consumer_key) { Db.remove(@/webmail/apps[~{oauth_consumer_key}]) }

  /** Export app configuration to /etc/peps directory. */
  function init() {
    App.list() |>
    List.iter(function (app) {
      config({success: app}, ignore)
    }, _)
  }

  /** Export app configuration (consumer secret) to the shared path /etc/peps/apps. */
  function config(result, callback) {
    match (result) {
      case {success: app}:
        port = Parser.parse(parser {
          case "http" ("s")? "://" (!":" .)* ":" port=Rule.integer .*: port
          case "http://" .*: 8080
          case "https://" .*: 4443
          case .*: 8080
        }, app.url)
        serverport = AppParameters.parameters.http_server_port ? AppConfig.http_server_port
        provider = "{Admin.get_domain()}:{serverport}"
        AppParameters.config(
          app.name, provider,
          app.oauth_consumer_key,
          app.oauth_consumer_secret,
          port
        )
      default: void
    }
    callback(result)
  }

} // END APP
