//
//  FollowersListVC.swift
//  GitHub Followers
//
//  Created by Eslam Nahel on 02/11/2021.
//

import UIKit

class FollowersListVC: UIViewController, Loadable {
    
    //MARK: - Component & Properties
    enum Section { case main }
    
    private var username: String!
    
    private var followers           = [Follower]()
    private var filteredFollowers   = [Follower]()
    
    private var page                = 1
    private var hasMoreFollowers    = true
    private var isSearching         = false
    private var isLoadingFollowers  = false
    
    private var collectionView: UICollectionView!
    private var dataSource: UICollectionViewDiffableDataSource<Section, Follower>!
    var containerView: UIView!
    
    
    //MARK: - Init methods
    init(username: String) {
        super.init(nibName: nil, bundle: nil)
        self.username   = username
        title           = username
    }
    
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    
    //MARK: - VC lifecycle methods
    override func viewDidLoad() {
        super.viewDidLoad()
        
        configureViewController()
        configureSearchController()
        configureCollectionView()
        getFollowers(username: username, page: page)
        configureDataSource()
    }
    
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        navigationController?.setNavigationBarHidden(false, animated: true)
    }
    
    
    //MARK: - Networking methods
    func getFollowers(username: String, page: Int) {
        showLoadingView()
        isLoadingFollowers = true
        NetworkManager.shared.getFollowers(for: username, page: page) { [weak self] results in
            guard let self = self else { return }
            self.hideLoadingView()
            switch results {
            case .success(let followers):
                self.updateFollowerList(with: followers)
            case .failure(let error):
                self.presentAlertOnMainThread(title: "Sth baaaad happened", message: error.rawValue, actionTitle: "Alrighty")
            }
            self.isLoadingFollowers = false
        }
    }
    
    
    private func updateFollowerList(with followers: [Follower]) {
        if followers.count < 100 {
            self.hasMoreFollowers = false
        }
        self.followers.append(contentsOf: followers)
        
        if self.followers.isEmpty {
            let message = "This user doesn't have any followers! Go and follow them 😉"
            DispatchQueue.main.async {
                self.showEmptyStateView(with: message, in: self.view)
            }
            return
        }
        
        DispatchQueue.main.async {
            self.updateData(on: self.followers)
        }
    }
    
    
    //MARK: - VC functionality methods
    @objc func addButtonTapped() {
        self.showLoadingView()
        NetworkManager.shared.getUserInfo(for: username) { [weak self] results in
            guard let self = self else { return }
            self.hideLoadingView()
            switch results {
            case .success(let favoriteInfo):
                self.addToFavoritesList(favoriteInfo: favoriteInfo)
            case .failure(let error):
                self.presentAlertOnMainThread(title: "Something went wrong!", message: error.rawValue, actionTitle: "Oki")
            }
        }
    }
    
    
    private func addToFavoritesList(favoriteInfo: User) {
        let favorite = Follower(login: favoriteInfo.login, avatarUrl: favoriteInfo.avatarUrl)
        PersistenceManager.shared.updateFavoritesList(with: favorite, actionType: .add) { [weak self] gfError in
            if let gfError = gfError {
                self?.presentAlertOnMainThread(title: "Something went wrong!", message: gfError.rawValue, actionTitle: "Oki")
                return
            }
            self?.presentAlertOnMainThread(title: "Success!", message: "You have saved this user to favorites 🥳", actionTitle: "Hooraay")
        }
    }
    
    
    //MARK: - Collection View data source methods
    func configureDataSource() {
        dataSource = UICollectionViewDiffableDataSource<Section, Follower>(collectionView: collectionView, cellProvider: { collectionView, indexPath, follower in
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: FollowerCell.reuseID, for: indexPath) as! FollowerCell
            cell.set(follower: follower)
            return cell
        })
    }
    
    
    func updateData(on followers: [Follower]) {
        var snapshot = NSDiffableDataSourceSnapshot<Section, Follower>()
        snapshot.appendSections([.main])
        snapshot.appendItems(followers)
        dataSource.apply(snapshot, animatingDifferences: true)
    }
    
    
    //MARK: - UI Configuration Methods
    private func configureViewController() {
        view.backgroundColor                                    = .systemBackground
        navigationController?.navigationBar.prefersLargeTitles  = true
        
        let addButton                                           = UIBarButtonItem(barButtonSystemItem: .add, target: self, action: #selector(addButtonTapped))
        navigationItem.rightBarButtonItem                       = addButton
    }
    
    
    private func configureCollectionView() {
        collectionView = UICollectionView(frame: view.bounds, collectionViewLayout: UIHelper.createFlowLayoutColumns(in: view))
        view.addSubview(collectionView)
        collectionView.delegate         = self
        collectionView.backgroundColor  = .systemBackground
        collectionView.register(FollowerCell.self, forCellWithReuseIdentifier: FollowerCell.reuseID)
    }
    
    
    private func configureSearchController() {
        let searchController                                    = UISearchController()
        searchController.searchResultsUpdater                   = self
        searchController.searchBar.placeholder                  = "Search for users"
        searchController.obscuresBackgroundDuringPresentation   = false
        navigationItem.hidesSearchBarWhenScrolling              = false
        navigationItem.searchController                         = searchController
    }
}


//MARK: - VC extensions
extension FollowersListVC: UICollectionViewDelegate {
    
    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        let offSetY         = scrollView.contentOffset.y + 170
        let contentHeight   = scrollView.contentSize.height
        let height          = scrollView.frame.size.height
        
        if offSetY >= contentHeight - height {
            guard hasMoreFollowers, !isLoadingFollowers else {
                return
            }
            self.page += 1
            self.getFollowers(username: username, page: page)
        }
    }
    
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let followersArray  = isSearching ? filteredFollowers : followers
        let follower        = followersArray[indexPath.item]
        
        let userInfoVC      = UserInfoVC()
        userInfoVC.delegate = self
        userInfoVC.userName = follower.login
        let navVC           = UINavigationController(rootViewController: userInfoVC)
        
        present(navVC, animated: true)
    }
}


extension FollowersListVC: UISearchResultsUpdating {
    
    func updateSearchResults(for searchController: UISearchController) {
        guard let filter = searchController.searchBar.text, !filter.isEmpty else {
            self.updateData(on: self.followers)
            filteredFollowers.removeAll()
            isSearching = false
            return
        }
        
        self.isSearching = true
        self.filteredFollowers = self.followers.filter {
            $0.login.lowercased().contains(filter.lowercased())
        }
        
        self.updateData(on: self.filteredFollowers)
    }
}


extension FollowersListVC: UserInfoVCDelegate {
    
    func didRequestFollowers(with username: String) {
        self.username   = username
        title           = username
        self.page       = 1
        
        self.followers.removeAll()
        self.filteredFollowers.removeAll()
        
        collectionView.scrollsToTop = true
        collectionView.scrollToItem(at: IndexPath(row: 0, section: 0), at: .top, animated: true)
        
        if isSearching {
            navigationItem.searchController?.searchBar.text = ""
            navigationItem.searchController?.isActive = false
            navigationItem.searchController?.dismiss(animated: false)
            isSearching = false
        }
        getFollowers(username: username, page: page)
    }
}

