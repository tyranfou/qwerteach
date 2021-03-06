require "administrate/base_dashboard"

class CommentDashboard < Administrate::BaseDashboard
  # ATTRIBUTE_TYPES
  # a hash that describes the type of each of the model's fields.
  #
  # Each different type represents an Administrate::Field object,
  # which determines how the attribute is displayed
  # on pages throughout the dashboard.
  ATTRIBUTE_TYPES = {
    sender: Field::BelongsTo.with_options(class_name: "User"),
    subject: Field::BelongsTo.with_options(class_name: "User"),
    id: Field::Number,
    sender_id: Field::Number,
    subject_id: Field::Number,
    comment_text: Field::Text,
    created_at: Field::DateTime,
    updated_at: Field::DateTime,
  }

  # COLLECTION_ATTRIBUTES
  # an array of attributes that will be displayed on the model's index page.
  #
  # By default, it's limited to four items to reduce clutter on index pages.
  # Feel free to add, remove, or rearrange items.
  COLLECTION_ATTRIBUTES = [
      :id,
      :sender,
      :subject,
      :comment_text,
  ]

  # SHOW_PAGE_ATTRIBUTES
  # an array of attributes that will be displayed on the model's show page.
  SHOW_PAGE_ATTRIBUTES = [
    :sender,
    :subject,
    :id,
    :sender_id,
    :subject_id,
    :comment_text,
    :created_at,
    :updated_at,
  ]

  # FORM_ATTRIBUTES
  # an array of attributes that will be displayed
  # on the model's form (`new` and `edit`) pages.
  FORM_ATTRIBUTES = [
      :sender,
      :subject,
      :comment_text,
  ]

  # Overwrite this method to customize how comments are displayed
  # across all pages of the admin dashboard.
  #
  # def display_resource(comment)
  #   "Comment ##{comment.id}"
  # end
end
