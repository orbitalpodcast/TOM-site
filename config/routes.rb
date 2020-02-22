Rails.application.routes.draw do
  root 'pages#index'

  get 'newsletter', to: 'users#new'
  resources :newsletter, controller: 'users', as: 'users', param: :access_token, except: [:index, :show, :destroy]
  resources :users, param: :access_token, only: [:index, :show, :destroy]
  get   'login',    to: 'sessions#new'
  post  'login',    to: 'sessions#create'
  get  'logout',    to: 'sessions#destroy'
  get 'welcome',    to: 'users#welcome' # TODO: move newsletter welcome to static controller

  get '/episodes/:begin/to/:end', to: 'episodes#index', as: 'episodes_with_range'
  get '/draft',                   to: 'episodes#draft'
  # Redirect legacy URLs
  get '/show-notes/:slug',        to: redirect('episodes/%{slug}')
  get '/show-notes/*date/:slug',  to: redirect('episodes/%{slug}')

  resources :episodes
  # Redirect direct paths
  get :episodes, path: '/:slug',   constraints: { slug: /[\w-]+/ }, to: redirect('episodes/%{slug}')
  get :episodes, path: '/:number', constraints: { number: /\d+/ },  to: redirect('episodes/%{number}')

  patch 'upload_image/:number', to: 'episodes#upload_image', as: 'upload_image'
  patch 'upload_audio/:number', to: 'episodes#upload_audio', as: 'upload_audio'

end
