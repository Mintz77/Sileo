//
//  SourcesViewController.swift
//  Sileo
//
//  Created by CoolStar on 9/22/19.
//  Copyright © 2019 Sileo Team. All rights reserved.
//

import Foundation

class SourcesViewController: SileoViewController {
    private var sortedRepoList: [Repo] = []
    var updatingRepoList: [Repo] = []
    
    private var tableView: SileoTableView?
    private var refreshControl = UIRefreshControl()
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        
        self.checkForUpdatesInBackground()
        
        weak var weakSelf: SourcesViewController? = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(self.checkForUpdatesInBackground),
                                               name: PackageListManager.reloadNotification,
                                               object: nil)
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(self.reloadRepo(_:)),
                                               name: RepoManager.progressNotification,
                                               object: nil)
    }
    
    func canEditRow(indexPath: IndexPath) -> Bool {
        if indexPath.section == 0 {
            return false
        }
        
        let repo = sortedRepoList[indexPath.row]
        return repo.entryFile.hasSuffix("/sileo.sources")
    }
    
    func controller(indexPath: IndexPath) -> CategoryViewController {
        let categoryVC = CategoryViewController(style: .plain)
        categoryVC.title = String(localizationKey: "All_Packages.Title")
        
        if indexPath.section == 1 {
            let repo = sortedRepoList[indexPath.row]
            categoryVC.repoContext = repo
            categoryVC.title = repo.repoName
        }
        
        return categoryVC
    }
    
    @objc func checkForUpdatesInBackground() {
        let repoManager = RepoManager.shared
        repoManager.checkUpdatesInBackground {
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView = SileoTableView(frame: .zero, style: .plain)
        view.addSubview(tableView!)
        tableView?.translatesAutoresizingMaskIntoConstraints = false
        tableView?.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        tableView?.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        tableView?.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        tableView?.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        tableView?.refreshControl = refreshControl
        refreshControl.addTarget(self, action: #selector(refreshSources(_:)), for: .valueChanged)
        
        self.title = String(localizationKey: "Sources_Page")
        tableView?.register(SourcesTableViewFooter.self, forHeaderFooterViewReuseIdentifier: "Sileo.SourcesTableViewFooter")
        
        updateSileoColors()
        weak var weakSelf = self
        NotificationCenter.default.addObserver(weakSelf as Any,
                                               selector: #selector(self.updateSileoColors),
                                               name: SileoThemeManager.sileoChangedThemeNotification,
                                               object: nil)
        
        tableView?.delegate = self
        tableView?.dataSource = self
        self.tableView?.separatorInset = UIEdgeInsets(top: 72, left: 0, bottom: 0, right: 0)
        self.tableView?.separatorColor = UIColor(white: 0, alpha: 0.2)
        self.setEditing(false, animated: false)
        
        self.registerForPreviewing(with: self, sourceView: self.tableView!)
        self.navigationController?.navigationBar.superview?.tag = WHITE_BLUR_TAG
        #if targetEnvironment(simulator) || targetEnvironment(macCatalyst)
        self.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "Refresh", style: .done, target: self, action: #selector(refreshSources(_:)))
        #endif
    }
    
    @objc func updateSileoColors() {
        self.tableView?.backgroundColor = .sileoBackgroundColor
        self.tableView?.separatorColor = .sileoSeparatorColor
        self.statusBarStyle = .default
        view.backgroundColor = .sileoBackgroundColor
    }
    
    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        updateSileoColors()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateSileoColors()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.navigationController?.navigationBar._hidesShadow = true
        self.tableView?.backgroundColor = .sileoBackgroundColor
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        self.navigationController?.navigationBar._hidesShadow = false
    }
    
    @objc func toggleEditing(_ sender: Any?) {
        self.setEditing(!self.isEditing, animated: true)
    }
    
    override func setEditing(_ editing: Bool, animated: Bool) {
        super.setEditing(editing, animated: animated)
        
        UIView.animate(withDuration: animated ? 0.2 : 0.0) {
            let nav = self.navigationItem
            nav.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(self.addSource(_:)))
            
            #if !targetEnvironment(simulator)
            if editing {
                let exportTitle = String(localizationKey: "Export")
                nav.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.toggleEditing(_:)))
                nav.rightBarButtonItem = UIBarButtonItem(title: exportTitle, style: .plain, target: self, action: #selector(self.exportSources(_:)))
            } else {
                nav.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .edit, target: self, action: #selector(self.toggleEditing(_:)))
            }
            #else
            if editing {
                nav.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .done, target: self, action: #selector(self.toggleEditing(_:)))
            }
            #endif
        }
    }
    
    @IBAction func refreshSources(_ sender: UIRefreshControl?) {
        self.refreshSources(forceUpdate: true, forceReload: true)
    }
    
    func refreshSources(forceUpdate: Bool, forceReload: Bool) {
        self.refreshSources(forceUpdate: forceUpdate, forceReload: forceReload, isBackground: false, useRefreshControl: false, useErrorScreen: true, completion: nil)
    }
    
    private func addToQueue(_ repo: Repo) {
        if !updatingRepoList.contains(where: { $0.rawURL == repo.rawURL }) {
            updatingRepoList.append(repo)
        }
    }
    
    private func removeFromQueue(_ repo: Repo) {
        if let index = updatingRepoList.firstIndex(where: { $0.rawURL == repo.rawURL }) {
            updatingRepoList.remove(at: index)
        }
    }
    
    private func killIndicator() {
        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""
        let badge = item?.view()?.value(forKey: "_badge") as? UIView ?? UIView()
        self.refreshControl.endRefreshing()
        let indicators = badge.subviews.filter { $0 is UIActivityIndicatorView }
        for indicator in indicators {
            if let indicator = indicator as? UIActivityIndicatorView {
                indicator.removeFromSuperview()
                indicator.stopAnimating()
            }
        }
        item?.badgeValue = nil
    }
    
    func refreshSources(forceUpdate: Bool, forceReload: Bool, isBackground: Bool, useRefreshControl: Bool, useErrorScreen: Bool, completion: ((Bool, NSAttributedString) -> Void)?) {
        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""
        guard let style = UIActivityIndicatorView.Style(rawValue: 5) else {
            fatalError("OK iOS...")
        }
        let indicatorView = UIActivityIndicatorView(style: style)
        let badge = item?.view()?.value(forKey: "_badge") as? UIView
        
        if updatingRepoList.isEmpty {
            indicatorView.frame = indicatorView.frame.offsetBy(dx: 2, dy: 2)
            indicatorView.startAnimating()
            badge?.addSubview(indicatorView)
            
            if useRefreshControl {
                if let tableView = self.tableView, let refreshControl = tableView.refreshControl, !refreshControl.isRefreshing {
                    refreshControl.beginRefreshing()
                    let yVal = -1 * (refreshControl.frame.maxY + tableView.adjustedContentInset.top)
                    tableView.setContentOffset(CGPoint(x: 0, y: yVal), animated: true)
                }
            }
        }
        
        for repo in sortedRepoList {
            addToQueue(repo)
        }
        
        RepoManager.shared.update(force: forceUpdate, forceReload: forceReload, isBackground: isBackground, completion: { didFindErrors, errorOutput in
            for repo in self.sortedRepoList {
                self.removeFromQueue(repo)
            }
            self.killIndicator()
            
            if didFindErrors, useErrorScreen {
                self.showRefreshErrorViewController(errorOutput: errorOutput, completion: nil)
            }
            
            if let completion = completion {
                completion(didFindErrors, errorOutput)
            }
        })
    }
    
    func updateSingleRepo(_ repo: Repo) {

        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""
        
        if updatingRepoList.isEmpty {
            let badge = item?.view()?.value(forKey: "_badge") as? UIView
            guard let style = UIActivityIndicatorView.Style(rawValue: 5) else {
                fatalError("OK iOS...")
            }
            let indicatorView = UIActivityIndicatorView(style: style)
            indicatorView.frame = indicatorView.frame.offsetBy(dx: 2, dy: 2)
            indicatorView.startAnimating()
            badge?.addSubview(indicatorView)
        }
        
        RepoManager.shared.update(force: true, forceReload: true, isBackground: false, repos: [repo], completion: { didFindErrors, errorOutput in
            self.removeFromQueue(repo)
            if self.updatingRepoList.isEmpty {
                self.killIndicator()
            }

            if didFindErrors {
                self.showRefreshErrorViewController(errorOutput: errorOutput, completion: nil)
            }
        })
    }
    
    func updateSpecific(_ repos: [Repo]) {
        let item = self.splitViewController?.tabBarItem
        item?.badgeValue = ""

        if updatingRepoList.isEmpty {
            let badge = item?.view()?.value(forKey: "_badge") as? UIView
            guard let style = UIActivityIndicatorView.Style(rawValue: 5) else {
                fatalError("OK iOS...")
            }
            let indicatorView = UIActivityIndicatorView(style: style)
            indicatorView.frame = indicatorView.frame.offsetBy(dx: 2, dy: 2)
            indicatorView.startAnimating()
            badge?.addSubview(indicatorView)
        }
        
        for repo in repos {
            addToQueue(repo)
        }
        
        RepoManager.shared.update(force: false, forceReload: true, isBackground: false, repos: repos) { [weak self] didFindErrors, errorOutput in
            guard let strongSelf = self else { return }
            for repo in repos {
                strongSelf.removeFromQueue(repo)
            }
            if strongSelf.updatingRepoList.isEmpty {
                strongSelf.killIndicator()
            }

            if didFindErrors {
                strongSelf.showRefreshErrorViewController(errorOutput: errorOutput, completion: nil)
            }
        }
    }
    
    func showRefreshErrorViewController(errorOutput: NSAttributedString, completion: (() -> Void)?) {
        let errorVC = SourcesErrorsViewController(nibName: "SourcesErrorsViewController", bundle: nil)
        errorVC.attributedString = errorOutput
        let navController = UINavigationController(rootViewController: errorVC)
        navController.navigationBar.barStyle = .blackTranslucent
        navController.modalPresentationStyle = .formSheet
        self.present(navController, animated: true, completion: completion)
    }
    
    func reSortList() {
        sortedRepoList = RepoManager.shared.repoList.sorted(by: { obj1, obj2 -> Bool in
            obj1.repoName.localizedCaseInsensitiveCompare(obj2.repoName) == .orderedAscending
        })
    }
    
    @objc func reloadRepo(_ notification: NSNotification) {
        if let repo = notification.object as? Repo {
            guard let idx = sortedRepoList.firstIndex(of: repo),
            let cell = self.tableView?.cellForRow(at: IndexPath(row: idx, section: 1)) as? SourcesTableViewCell else {
                return
            }
            let cellRepo = cell.repo
            cell.repo = cellRepo
            cell.layoutSubviews()
        } else if let count = notification.object as? Int {
            DispatchQueue.main.async {
                guard let cell = self.tableView?.cellForRow(at: IndexPath(row: 0, section: 0)) as? SourcesTableViewCell else { return }
                cell.installedLabel.text = "\(count)"
            }
        } else {
            for cell in tableView?.visibleCells ?? [] {
                if let sourcesCell = cell as? SourcesTableViewCell {
                    let cellRepo = sourcesCell.repo
                    sourcesCell.repo = cellRepo
                    sourcesCell.layoutSubviews()
                }
            }
        }
    }
    
    func reloadData() {
        self.reSortList()
        self.tableView?.reloadData()
    }
    
    @objc func exportSources(_ sender: Any?) {
        let titleString = String(localizationKey: "Export")
        let msgString = String(localizationKey: "Export_Sources")
        let alert = UIAlertController(title: titleString, message: msgString, preferredStyle: .alert)
        
        let yesString = String(localizationKey: "Export_Yes")
        let yesAction = UIAlertAction(title: yesString, style: .default, handler: { _ in
            UIPasteboard.general.string = self.sortedRepoList.map({ $0.rawURL }).joined(separator: "\n")
        })
        alert.addAction(yesAction)
        
        let noString = String(localizationKey: "Export_No")
        let noAction = UIAlertAction(title: noString, style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(noAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    public func presentAddSourceEntryField(url: URL?) {
        let title = String(localizationKey: "Add_Source.Title")
        let msg = String(localizationKey: "Add_Source.Body")
        let alert = UIAlertController(title: title, message: msg, preferredStyle: .alert)
        
        alert.addTextField { textField in
            textField.placeholder = "https://coolstar.org/publicrepo/"
            if let urlString = url?.absoluteString {
                let parsedURL = urlString.replacingOccurrences(of: "sileo://source/", with: "")
                textField.text = parsedURL
            } else {
                textField.text = "https://"
            }
            textField.keyboardType = .URL
        }
        
        let addAction = UIAlertAction(title: String(localizationKey: "Add_Source.Button.Add"), style: .default, handler: { _ in
            self.dismiss(animated: true, completion: nil)
            if let repoURL = alert.textFields?[0].text,
                let url = URL(string: repoURL) {
                self.handleSourceAdd(urls: [url], bypassFlagCheck: false)
            }
        })
        alert.addAction(addAction)
        
        let cancelAcction = UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(cancelAcction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    func presentAddClipBoardPrompt(sources: [URL]) {
        if sources.isEmpty {
            // I'm not quite sure how this happens, but it does sooooo
            return self.presentAddSourceEntryField(url: nil)
        }
        let count = sources.count

        let titleText = String(format: String(localizationKey: "Auto_Add_Pasteboard_Sources.Title"), count, count)
        let addText = String(format: String(localizationKey: "Auto_Add_Pasteboard_Sources.Button.Add"), count, count)
        let manualText = String(localizationKey: "Auto_Add_Pasteboard_Sources.Button.Manual")
        
        var msg = String(format: String(localizationKey: "Auto_Add_Pasteboard_Sources.Body_Intro"), sources.count)
        msg.append(contentsOf: "\n\n")
        let urlsJoined = sources.compactMap { url -> String in
            url.absoluteString
        }.joined(separator: "\n")
        msg.append(contentsOf: urlsJoined)
        
        let alert = UIAlertController(title: titleText, message: msg, preferredStyle: .alert)
        
        let addAction = UIAlertAction(title: addText, style: .default, handler: { _ in
            self.handleSourceAdd(urls: sources, bypassFlagCheck: false)
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(addAction)
        
        let manualAction = UIAlertAction(title: manualText, style: .default, handler: { _ in
            self.presentAddSourceEntryField(url: nil)
        })
        alert.addAction(manualAction)
        
        let cancelAction = UIAlertAction(title: String(localizationKey: "Cancel"), style: .cancel, handler: { _ in
            self.dismiss(animated: true, completion: nil)
        })
        alert.addAction(cancelAction)
        
        self.present(alert, animated: true, completion: nil)
    }
    
    @objc func addSource(_ sender: Any?) {
        // If URL(s) are copied, we ask the user if they want to add those.
        // Otherwise, we present the entry field dialog for the user to type a URL.
        if #available(iOS 14.0, *) {
            UIPasteboard.general.detectPatterns(for: [.probableWebURL]) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let pattern) where pattern.contains(.probableWebURL):
                        let newSources = UIPasteboard.general.newSources()
                        self.presentAddClipBoardPrompt(sources: newSources)
                    case .success, .failure:
                        self.presentAddSourceEntryField(url: nil)
                    }
                }
            }
        } else {
            let newSources = UIPasteboard.general.newSources()
            if newSources.isEmpty {
                self.presentAddSourceEntryField(url: nil)
            } else {
                self.presentAddClipBoardPrompt(sources: newSources)
            }
        }
    }

    func showFlaggedSourceWarningController(urls: [URL]) {
        let flaggedSourceController = FlaggedSourceWarningViewController(nibName: "FlaggedSourceWarningViewController", bundle: nil)
        flaggedSourceController.shouldAddAnywayCallback = {
            self.handleSourceAdd(urls: urls, bypassFlagCheck: true)
            self.refreshSources(forceUpdate: false, forceReload: false)
        }
        flaggedSourceController.urls = urls
        flaggedSourceController.modalPresentationStyle = .formSheet
        present(flaggedSourceController, animated: true)
    }
    
    func handleSourceAdd(urls: [URL], bypassFlagCheck: Bool) {
        if !bypassFlagCheck {
            CanisterResolver.piracy(urls) { safe, piracy in
                DispatchQueue.main.async {
                    if !safe.isEmpty {
                        let repos = RepoManager.shared.addRepos(with: safe)
                        if !repos.isEmpty {
                            self.reloadData()
                            self.updateSpecific(repos)
                        }
                        self.reloadData()
                        self.refreshSources(forceUpdate: false, forceReload: false)
                    }
                    if !piracy.isEmpty {
                        self.showFlaggedSourceWarningController(urls: piracy)
                    }
                }
            }
        } else {
            let repos = RepoManager.shared.addRepos(with: urls)
            if !repos.isEmpty {
                self.reloadData()
                self.updateSpecific(repos)
            }
        }
    }
}

extension SourcesViewController: UITableViewDataSource { // UITableViewDataSource
    func numberOfSections(in tableView: UITableView) -> Int {
        2
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        if section == 0 {
            return 1
        } else {
            self.reSortList()
            return sortedRepoList.count
        }
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return (section == 1) ? String(localizationKey: "Repos") : nil
    }
    
    func tableView(_ tableView: UITableView, viewForHeaderInSection section: Int) -> UIView? {
        let text = self.tableView(tableView, titleForHeaderInSection: section)
        let headerView = UIView(frame: CGRect(origin: .zero, size: CGSize(width: 320, height: 36)))
        
        if let text = text {
            let headerBlur = UIToolbar(frame: headerView.bounds)
            headerView.tag = WHITE_BLUR_TAG
            headerBlur._hidesShadow = true
            headerBlur.autoresizingMask = [.flexibleWidth, .flexibleBottomMargin]
            headerView.addSubview(headerBlur)
            
            let titleView = SileoLabelView(frame: CGRect(x: 16, y: 0, width: 320, height: 28))
            titleView.font = UIFont.systemFont(ofSize: 22, weight: .bold)
            titleView.text = text
            titleView.autoresizingMask = .flexibleWidth
            headerView.addSubview(titleView)
            
            let separatorView = SileoSeparatorView(frame: CGRect(x: 16, y: 35, width: 304, height: 1))
            separatorView.autoresizingMask = .flexibleWidth
            headerView.addSubview(separatorView)
        }
        
        return headerView
    }
    
    func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        switch section {
        case 0:
            return 5
        case 1:
            return 44
        default:
            return 0
        }
    }
    
    func tableView(_ tableView: UITableView, viewForFooterInSection section: Int) -> UIView? {
        guard section == 1 else { return UIView() }
        
        let footerView = SourcesTableViewFooter(reuseIdentifier: "Sileo.SourcesTableViewFooter")
        footerView.setCount(sortedRepoList.count)
        return footerView
    }
    
    func tableView(_ tableView: UITableView, heightForFooterInSection section: Int) -> CGFloat {
        return (section == 0) ? 2 : 30
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = (tableView.dequeueReusableCell(withIdentifier: "SourcesViewControllerCellidentifier") as? SourcesTableViewCell) ??
            SourcesTableViewCell(style: .subtitle, reuseIdentifier: "SourcesViewControllerCellidentifier")
        
        if indexPath.section == 0 {
            cell.repo = nil
        } else {
            cell.repo = sortedRepoList[indexPath.row]
        }
        
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        55
    }
    
    private func updateFooterCount() {
        if let footerView = tableView?.footerView(forSection: 1) as? SourcesTableViewFooter {
            footerView.setCount(sortedRepoList.count)
        }
    }
}

extension SourcesViewController: UITableViewDelegate { // UITableViewDelegate
    func tableView(_ tableView: UITableView, shouldShowMenuForRowAt indexPath: IndexPath) -> Bool {
        indexPath.section > 0
    }
    
    func tableView(_ tableView: UITableView, canPerformAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) -> Bool {
        action == #selector(UIResponderStandardEditActions.copy(_:))
    }
    
    func tableView(_ tableView: UITableView, performAction action: Selector, forRowAt indexPath: IndexPath, withSender sender: Any?) {
        if action != #selector(UIResponderStandardEditActions.copy(_:)) {
            return
        }
        
        let repo = sortedRepoList[indexPath.row]
        UIPasteboard.general.url = repo.url
    }
    
    func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        true
    }
    
    func tableView(_ tableView: UITableView, editingStyleForRowAt indexPath: IndexPath) -> UITableViewCell.EditingStyle {
        if !self.canEditRow(indexPath: indexPath) {
            return .none
        }
        return .delete
    }
    
    func tableView(_ tableView: UITableView, shouldIndentWhileEditingRowAt indexPath: IndexPath) -> Bool {
        self.canEditRow(indexPath: indexPath)
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let categoryVC = self.controller(indexPath: indexPath)
        let navController = SileoNavigationController(rootViewController: categoryVC)
        self.splitViewController?.showDetailViewController(navController, sender: self)
    }
    
    func tableView(_ tableView: UITableView,
                   trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath) -> UISwipeActionsConfiguration? {
        // We don't want to be able to delete the top section so we just return early here
        if indexPath.section == 0 { return nil }
        // We're using this a bunch, best just keep it here
        let repoManager = RepoManager.shared
        let refresh = UIContextualAction(style: .normal, title: String(localizationKey: "Refresh")) { _, _, completionHandler in
            self.updateSingleRepo(self.sortedRepoList[indexPath.row])
            completionHandler(true)
        }
        refresh.backgroundColor = .systemGreen
        if !self.canEditRow(indexPath: indexPath) {
            return UISwipeActionsConfiguration(actions: [refresh])
        }
        let remove = UIContextualAction(style: .destructive, title: String(localizationKey: "Remove")) { _, _, completionHandler in
            repoManager.remove(repo: self.sortedRepoList[indexPath.row])
            
            self.reSortList()
            tableView.deleteRows(at: [indexPath], with: .fade)
            
            self.updateFooterCount()
            self.refreshSources(forceUpdate: false, forceReload: true)
            completionHandler(true)
        }
        return UISwipeActionsConfiguration(actions: [remove, refresh])
    }
}

extension SourcesViewController: UIViewControllerPreviewingDelegate {
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, viewControllerForLocation location: CGPoint) -> UIViewController? {
        guard let indexPath = self.tableView?.indexPathForRow(at: location) else {
            return nil
        }
        
        let categoryVC = self.controller(indexPath: indexPath)
        return categoryVC
    }
    
    func previewingContext(_ previewingContext: UIViewControllerPreviewing, commit viewControllerToCommit: UIViewController) {
        let navController = SileoNavigationController(rootViewController: viewControllerToCommit)
        self.splitViewController?.showDetailViewController(navController, sender: self)
    }
}
